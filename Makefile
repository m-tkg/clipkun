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

# ベータ（pre-release）タグ v<version>-beta.<N> を切る。N は既存のベータ番号 +1 で自動採番。
# Info.plist の CFBundleShortVersionString はそのまま（数値のまま）で、ベータはそのタグだけで切れる。
# ワークフローは "-" を含むタグを GitHub pre-release として公開し、/releases/latest（＝通常の
# 更新チェック）はそれを無視する。ベータ検証者は手動で zip を入れる。
.PHONY: beta-tag
beta-tag:
	@if [ -z "$(VERSION)" ]; then \
		echo "error: CFBundleShortVersionString not found in Resources/Info.plist" >&2; \
		exit 1; \
	fi
	@branch="$$(git rev-parse --abbrev-ref HEAD)"; \
	if [ "$$branch" != "main" ]; then \
		echo "error: must be on main to cut a beta (current: $$branch)" >&2; \
		exit 1; \
	fi
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "error: working tree is not clean" >&2; \
		exit 1; \
	fi
	@git fetch origin main --tags --quiet
	@if [ "$$(git rev-parse HEAD)" != "$$(git rev-parse origin/main)" ]; then \
		echo "error: local main is not up to date with origin/main" >&2; \
		exit 1; \
	fi
	@n=1; while git rev-parse "v$(VERSION)-beta.$$n" >/dev/null 2>&1; do n=$$((n+1)); done; \
	tag="v$(VERSION)-beta.$$n"; \
	git tag -a "$$tag" -m "Beta $$tag"; \
	git push origin "$$tag"; \
	echo "Pushed beta tag $$tag; the release workflow will build and publish it as a pre-release."
