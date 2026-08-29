.PHONY: all build run spike test app install clean help

# Default target
all: build

## help: Display this help message
help:
	@echo "LyriaFlow - Minimalist macOS Music Player"
	@echo "Available make targets:"
	@echo "  make build    - Compile debug binaries"
	@echo "  make run      - Run the LyriaFlow macOS SwiftUI app"
	@echo "  make spike    - Run the Lyria MCP verification spike"
	@echo "  make test     - Run automated unit test suite"
	@echo "  make app      - Build standalone LyriaFlow.app release bundle"
	@echo "  make install  - Install LyriaFlow.app into ~/Applications"
	@echo "  make clean    - Remove build artifacts and temporary files"

## build: Compile Swift packages
build:
	@echo "🔨 Building LyriaFlow..."
	@swift build

## run: Launch the LyriaFlow GUI app
run:
	@echo "🚀 Launching LyriaFlow..."
	@swift run LyriaFlow

## spike: Run the MCP verification test harness
spike:
	@echo "🎵 Running Lyria MCP Spike..."
	@swift run LyriaFlowSpike

## test: Run unit tests
test:
	@echo "🧪 Running unit tests..."
	@swift test

## app: Build release .app bundle
app:
	@echo "📦 Packaging LyriaFlow.app..."
	@./scripts/build_app.sh

## install: Install the app into ~/Applications
install: app
	@echo "📲 Installing LyriaFlow.app into ~/Applications..."
	@mkdir -p ~/Applications
	@rm -rf ~/Applications/LyriaFlow.app
	@cp -R LyriaFlow.app ~/Applications/
	@echo "✅ Installed LyriaFlow.app in ~/Applications!"

## clean: Clean build directory and generated app bundles
clean:
	@echo "🧹 Cleaning workspace..."
	@swift package clean
	@rm -rf .build LyriaFlow.app
	@echo "✅ Clean complete."
