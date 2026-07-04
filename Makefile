VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist 2>/dev/null)
TAG := v$(VERSION)

.PHONY: release-tag
release-tag:
	@if [ -z "$(VERSION)" ]; then \
		echo "error: CFBundleShortVersionString not found in Resources/Info.plist" >&2; \
		exit 1; \
	fi
	@branch="$$(git rev-parse --abbrev-ref HEAD)"; \
	if [ "$$branch" != "main" ]; then \
		echo "error: must be on main to cut a release (current: $$branch)" >&2; \
		exit 1; \
	fi
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "error: working tree is not clean" >&2; \
		exit 1; \
	fi
	@git fetch origin main --quiet
	@if [ "$$(git rev-parse HEAD)" != "$$(git rev-parse origin/main)" ]; then \
		echo "error: local main is not up to date with origin/main" >&2; \
		exit 1; \
	fi
	@if git rev-parse "$(TAG)" >/dev/null 2>&1; then \
		echo "error: tag $(TAG) already exists" >&2; \
		exit 1; \
	fi
	git tag -a "$(TAG)" -m "Release $(TAG)"
	git push origin "$(TAG)"
	@echo "Pushed tag $(TAG); the release workflow will build and publish it."
