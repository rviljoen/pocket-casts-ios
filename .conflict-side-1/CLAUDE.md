@AGENTS.md
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pocket Casts is an open-source iOS podcast application by Automattic. The project uses a modular architecture with Swift Package Manager modules and supports multiple Apple platforms (iOS, watchOS, App Clips).

## Essential Commands

### Initial Setup
```bash
# Install dependencies (CocoaPods, Ruby gems)
make install_dependencies

# External contributors setup (creates empty API credentials)
make external_contributor
```

### Development
```bash
# Code formatting and linting
make format

# Manual linting check
make lint

# Update protocol buffers (requires API_PATH to protobuf files)
make update_proto API_PATH={path_to_protobuf}
```

### Testing
```bash
# Run all tests via Fastlane
bundle exec fastlane test

# Run specific test plans
xcodebuild test -workspace podcasts.xcworkspace -scheme PocketCastsTests -testPlan UnitTests
```

### Building
- **IMPORTANT**: Always open `podcasts.xcworkspace`, never the `.xcodeproj` file
- Use Xcode 16.2+ with iOS 16.0+ deployment target
- Multiple build configurations available: debug, release, staging, prototype

## Project Architecture

### Modular Structure
The codebase uses three Swift Package Manager modules in `/Modules/`:

- **DataModel**: Database layer (FMDB/GRDB), Core Data models, persistence logic
- **Server**: API communication, sync protocols, networking, authentication  
- **Utils**: Shared utilities, extensions, formatters, helpers

### Main Targets
- **podcasts**: Primary iOS application
- **Pocket Casts Watch App**: Apple Watch companion app
- **Pocket Casts App Clip**: Lightweight app experience  
- **Extensions**: Notifications, Intents/Siri, Share, Widgets

### Configuration Management
- Build settings managed via `.xcconfig` files in `/config/`
- Version controlled in `config/Version.xcconfig` (currently 7.90.0.3)
- Environment-specific configurations for debug/release/staging/prototype

## Key Development Patterns

### Data Layer
- Uses both FMDB and GRDB for database operations
- Repository pattern with `DataManager` classes
- Core model objects: `Podcast`, `Episode`, `UserEpisode`, `Folder`

### Networking & Sync
- Protocol Buffers for server communication
- Robust sync system for cross-device functionality
- Upload management for user-generated content

### UI Architecture  
- Primarily UIKit with SwiftUI components
- Comprehensive theming system (`Theme`, `ThemeableView` hierarchy)
- Custom controls and animations throughout

### Testing Strategy
- Comprehensive unit test suite in `/PocketCastsTests/`
- Each SPM module has dedicated test targets
- Test plan configuration with CI/CD integration
- Mock objects and test utilities in `/PocketCastsTests/Mocks/`

## Dependencies & Package Management

### CocoaPods
- Primary dependency: `google-cast-sdk-no-bluetooth` for Chromecast support
- Development tools: SwiftLint (code formatting), SwiftGen (localization)
- Uses modular headers and inhibits warnings

### Swift Package Manager
- Local modules for modular architecture
- External dependencies for database and networking

## Important Notes

### External Contributors
- Run `make external_contributor` to generate empty API credentials
- This creates `LocalApiCredentials.swift` with placeholder values

### Code Quality
- SwiftLint enforced - run `make format` before commits
- Comprehensive localization support via GlotPress
- Protocol Buffer files require separate API repository access

### Fastlane Integration
- Extensive CI/CD pipeline for releases, testing, localization
- Screenshot automation for App Store submissions  
- Code signing and distribution management

### Branch Strategy
- Main branch: `trunk`
- Release branches follow `release/x.y.z` pattern
- Current development may use GitButler workspace branches

## Common Development Tasks

### Adding New Features
1. Consider which module the feature belongs in (DataModel/Server/Utils vs main app)
2. Follow existing patterns for theming and accessibility
3. Add appropriate unit tests
4. Update localizations if needed

### Working with Database
- Use existing `DataManager` patterns
- Consider both FMDB and GRDB compatibility
- Follow migration patterns for schema changes

### UI Development
- Inherit from `ThemeableView` hierarchy for consistent theming
- Use existing custom controls and animations
- Follow accessibility patterns established in codebase

### Protocol Buffer Updates
- Requires access to separate `pocketcasts-api` repository
- Use `make update_proto` with proper API_PATH
- Install protobuf and swift-protobuf via Homebrew first
