CONFIGURATION ?= debug

.PHONY: help build run test verify release clean

help:
	@echo 'make build           Build the Mac app (CONFIGURATION=debug|release)'
	@echo 'make run             Build and launch the Mac app (CONFIGURATION=debug|release)'
	@echo 'make test            Run core regression tests'
	@echo 'make verify          Verify project boundaries, versions, and attributions'
	@echo 'make release         Build Universal release app'
	@echo 'make clean           Clean build artifacts, intermediate files, and review output'

build:
	scripts/build-app.sh $(CONFIGURATION)

run:
	scripts/compile_and_run.sh $(CONFIGURATION)

test:
	swift test

verify:
	scripts/verify-project.sh

release:
	scripts/build-app.sh release --universal

clean:
	rm -rf .build artifacts screenshots
	@echo 'Cleaned .build, artifacts, and screenshots.'
