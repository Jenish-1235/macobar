# Generates the Xcode project from project.yml.
generate:
	xcodegen generate --quiet

# Builds a Debug app into ./build.
build: generate
	xcodebuild -project Macobar.xcodeproj -scheme Macobar -configuration Debug -derivedDataPath build -quiet build

# Builds and launches macobar.
run: build
	open build/Build/Products/Debug/Macobar.app

# Runs the logic tests.
test: generate
	xcodebuild -project Macobar.xcodeproj -scheme Macobar -derivedDataPath build -destination "platform=macOS,arch=arm64" -quiet test

.PHONY: generate build run test
