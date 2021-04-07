# Reading List
[![Build Status](https://travis-ci.com/AndrewBennet/ReadingList.svg?branch=master)](https://travis-ci.com/AndrewBennet/ReadingList)
[![codebeat badge](https://codebeat.co/badges/3f7723a7-8967-436e-b5e9-549e0261603c)](https://codebeat.co/projects/github-com-andrewbennet-readinglist)
[![Twitter URL](https://img.shields.io/twitter/url?label=%40ReadingListApp&style=social&url=https%3A%2F%2Ftwitter.com%2Freadinglistapp)](https://twitter.com/ReadingListApp)

[Reading List](https://www.readinglist.app) is an iOS app for iPhone and iPad which helps users track and catalog the books they read.

## Reading List v2
As of version 2.0, Reading List is no longer open source. The app is instead supported by some select premium features which require a one-time payment to unlock. The codebase here is as it existed in v1.16.1.

<img src="./media/iPhone%20X-0_ToReadList_framed.png" width="280"></img>

<a href="https://itunes.apple.com/us/app/reading-list-book-log/id1217139955?mt=8">
  <img src="https://linkmaker.itunes.apple.com/assets/shared/badges/en-us/appstore-lrg.svg" style="height: 60px;"/>
</a>

<a href="https://testflight.apple.com/join/kBS5mVao">
  <img src="https://developer.apple.com/assets/elements/icons/testflight/testflight-64x64_2x.png" height="45px" />
</a>

## Requirements
 - Xcode 12.4

## Dependencies

Reading List uses the [Mint](https://github.com/yonaskolb/Mint) package manager to manage Swift command line tool packages. Mint can be installed using [Homebrew](https://brew.sh/) (among [other methods](https://github.com/yonaskolb/Mint#installing)):

    brew install mint

### XcodeGen
XcodeGen is a command-line tool written in Swift. It generates your Xcode project using your folder structure and a project spec, which contains all the information necessary to generate a project, such as targets, schemes, settings.
The Xcode project should be generated by running [XcodeGen](https://github.com/yonaskolb/XcodeGen):

    mint run yonaskolb/XcodeGen

### SwiftLint
[SwiftLint](https://github.com/realm/SwiftLint) is used to enforce Swift style guidelines. An Xcode build step runs SwiftLint; this requires it to be installed. To install it, run:

    mint install realm/SwiftLint

## Architecture
Reading List is written in Swift, and primarily uses Apple provided technologies.

### User Interface
Reading List mostly uses [storyboards](https://developer.apple.com/library/content/documentation/General/Conceptual/Devpedia-CocoaApp/Storyboard.html) for UI design (see below); a limited number of user input views are built using [Eureka](https://github.com/xmartlabs/Eureka) forms.

![Example storyboard](./media/storyboard.png)

### Data persistence
Reading List uses [Core Data](https://developer.apple.com/documentation/coredata) for data persistence. There are three entities used in Reading List: `Book`, `Subject` and `List`. The attributes and relations between then are illustrated below:

<img src="./media/coredata_entities.png" width="400px;" alt="Core data entities"/>
