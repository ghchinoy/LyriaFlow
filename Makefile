.PHONY: all build run run-cli spike test app install clean help

# Default target
all: build

## help: Display this help message
help:
	@echo "LyriaFlow - Minimalist macOS Music Player"
	@echo "Available make targets:"
	@echo "  make run      - Fast build & launch LyriaFlow.app"
	@echo "  make run-cli  - Launch directly in Terminal via swift run"
	@echo "  make build    - Compile debug binaries"
	@echo "  make spike    - Run the Lyria MCP verification spike"
	@echo "  make test     - Run automated unit test suite"
	@echo "  make app      - Build optimized release LyriaFlow.app bundle"
	@echo "  make install  - Install release LyriaFlow.app into ~/Applications"
	@echo "  make clean    - Remove build artifacts and temporary files"

## build: Compile Swift packages
build:
	@echo "🔨 Building LyriaFlow..."
	@swift build

## run: Fast build and launch GUI app
run:
	@./scripts/build_app.sh
	@echo "🚀 Opening LyriaFlow.app..."
	@open LyriaFlow.app

## run-cli: Launch directly via swift run
run-cli:
	@echo "🚀 Launching LyriaFlow in terminal..."
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
	@./scripts/build_app.sh --release

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
