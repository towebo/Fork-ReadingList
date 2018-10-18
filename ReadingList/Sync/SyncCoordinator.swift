import Foundation
import CoreData
import UIKit
import CloudKit

/**
 Coordinates synchronisation of a local CoreData store with a CloudKit remote store.
*/
class SyncCoordinator {

    private let viewContext: NSManagedObjectContext
    private let syncContext: NSManagedObjectContext

    private let upstreamChangeProcessors: [UpstreamChangeProcessor]
    private let downstreamChangeProcessors: [DownstreamChangeProcessor]

    let remote = BookCloudKitRemote()

    private var contextSaveNotificationObservers = [NSObjectProtocol]()

    init(container: NSPersistentContainer) {
        viewContext = container.viewContext
        viewContext.name = "viewContext"

        syncContext = container.newBackgroundContext()
        syncContext.name = "syncContext"
        syncContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump // FUTURE: Add a custom merge policy

        self.downstreamChangeProcessors = [BookDownloader(syncContext)]
        self.upstreamChangeProcessors = [BookUploader(syncContext, remote),
                                         BookDeleter(syncContext, remote)]
    }

    /**
     Starts monitoring for changes in CoreData, and immediately process any outstanding pending changes.
     */
    func start() {
        syncContext.perform {
            self.syncContext.refreshAllObjects()
            self.startContextNotificationObserving()
            self.processPendingChanges()
        }
    }

    var isStarted: Bool {
        return !contextSaveNotificationObservers.isEmpty
    }

    /**
     Stops the monitoring of CoreData changes.
    */
    func stop() {
        contextSaveNotificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        contextSaveNotificationObservers.removeAll()
    }

    /**
     Registers Save observers on both the viewContext and the syncContext, handling them by merging the save from
     one context to the other, and also calling `processPendingLocalChanges(objects:)` on the updated or inserted objects.
    */
    private func startContextNotificationObserving() {
        guard contextSaveNotificationObservers.isEmpty else { print("Observers already registered"); return }

        func registerForMergeOnSave(from sourceContext: NSManagedObjectContext, to destinationContext: NSManagedObjectContext) {
            let observer = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave, object: sourceContext, queue: nil) { [weak self] note in

                // Merge the changes into the destination context, on the appropriate thread
                print("Merging save from \(String(sourceContext.name!)) to \(String(destinationContext.name!))")
                destinationContext.performMergeChanges(from: note)

                // Take the new or modified objects, mapped to the syncContext, and process them as local changes.
                // There may be nothing to perform with these local objects; the eligibility of the objects will
                // be checked within processPendingLocalChanges(objects:).
                guard let coordinator = self else { return }
                coordinator.syncContext.perform {
                    // We unpack the notification here, to make sure it is retained until this point.
                    let updates = note.updatedObjects?.map { $0.inContext(coordinator.syncContext) } ?? []
                    let inserts = note.insertedObjects?.map { $0.inContext(coordinator.syncContext) } ?? []
                    let localChanges = updates + inserts
                    if !localChanges.isEmpty {
                        coordinator.processPendingLocalChanges(objects: localChanges)
                    }
                }
            }
            contextSaveNotificationObservers.append(observer)
        }

        registerForMergeOnSave(from: syncContext, to: viewContext)
        registerForMergeOnSave(from: viewContext, to: syncContext)
    }

    /**
     Processes all pending changes: remote changes are retrieved and then local changes are uploaded.
    */
    func processPendingChanges() {
        syncContext.perform {
            self.processPendingRemoteChanges()
            self.processPendingLocalChanges()
        }
    }

    /**
     Requests any remote changes, merging them into the local store.
    */
    func remoteNotificationReceived(applicationCallback: ((UIBackgroundFetchResult) -> Void)? = nil) {
        syncContext.perform {
            self.processPendingRemoteChanges(applicationCallback: applicationCallback)
        }
    }

    // We prevent the processing objects that are already being processed. This is an easy way to prevent some
    // errors on the CloudKit end, like uploading a new book twice, due to its creation and a successive edit
    // (before the creation's callback runs).
    private var objectsBeingProcessed = Set<NSManagedObject>()

    private func processPendingLocalChanges(objects: [NSManagedObject]? = nil) {
        for changeProcessor in upstreamChangeProcessors {
            // If we were passed some pending objects, select the ones which are pending a change process.
            // Otherwise, select all pending objects. We always exclude objects which are already being processed.
            let objectToProcess: [NSManagedObject]
            if let objects = objects {
                objectToProcess = objects.filter { object($0, isPendingFor: changeProcessor) && !objectsBeingProcessed.contains($0) }
            } else {
                objectToProcess = self.pendingObjects(for: changeProcessor).filter { !objectsBeingProcessed.contains($0) }
            }

            // Quick exit if there are no pending objects
            guard !objectToProcess.isEmpty else { continue }

            // Track which objects are passed to the change processor. They will not be passed to any other
            // change processor until this one has run its completion block.
            objectsBeingProcessed.formUnion(objectToProcess)
            changeProcessor.processLocalChanges(objectToProcess) { [weak self] in
                self?.objectsBeingProcessed.subtract(objectToProcess)
            }
        }

        // TODO: Re-process the objects which are still eligible for processing after this operation?
        // TODO: This could be due to local edits which occurred while the remote update operation
        // TODO: was pending.
    }

    private func processPendingRemoteChanges(applicationCallback: ((UIBackgroundFetchResult) -> Void)? = nil) {
        let storedChangeToken = ChangeToken.get(fromContext: self.syncContext, for: self.remote.bookZoneID)

        remote.fetchRecordChanges(changeToken: storedChangeToken?.changeToken) { error, changes in
            guard let changes = changes else {
                self.handleFetchChangesError(error: error!, changeToken: storedChangeToken)
                return
            }

            guard !changes.isEmpty else {
                applicationCallback?(UIBackgroundFetchResult.noData)
                return
            }

            for changeProcessor in self.downstreamChangeProcessors {
                changeProcessor.processRemoteChanges(from: self.remote.bookZoneID, changes: changes) {
                    applicationCallback?(UIBackgroundFetchResult.newData)
                }
            }
        }
    }

    private func handleFetchChangesError(error: Error, changeToken: ChangeToken?) {
        if let ckError = error as? CKError {
            switch ckError.strategy {
            case .resetChangeToken:
                self.syncContext.perform {
                    changeToken!.deleteAndSave()
                }
            case .disableSync, .retryLater, .manualMerge, .retrySmallerBatch, .none, .handleInnerErrors:
                fatalError("Unexpected strategy for failing change fetch: \(ckError.strategy), or error code \(ckError.code)")
            }
        } else {
            print("Unexpected error")
        }
    }

    private func pendingObjects(for changeProcessor: UpstreamChangeProcessor) -> [NSManagedObject] {
        let fetchRequest = changeProcessor.unprocessedChangedObjectsRequest
        fetchRequest.returnsObjectsAsFaults = false
        return try! syncContext.fetch(fetchRequest) as! [NSManagedObject]
    }

    private func object(_ object: NSManagedObject, isPendingFor changeProcessor: UpstreamChangeProcessor) -> Bool {
        let fetchRequest = changeProcessor.unprocessedChangedObjectsRequest
        // Entity name comparison is done since the NSEntityDescription is not necessarily present until a fetch has been peformed
        return object.entity.name == fetchRequest.entityName && fetchRequest.predicate?.evaluate(with: object) != false
    }
}
