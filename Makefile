.PHONY: docs gen lock build test lint dev install release release-dry-run clean

APP = Seam
CONFIG ?= Debug
DERIVED = build

# CHANGELOG lebt im Repo-Wurzelverzeichnis und wird bei jedem Build ins Bundle
# gespiegelt (Kalli-Muster): Die App kann nie eine ältere Fassung anzeigen.
docs:
	cp CHANGELOG.md Seam/Resources/CHANGELOG.md

# Lockfile lebt im Repo, das Projekt ist generiert (gitignoriert). Ohne Einspielen
# wäre Sparkles Commit-SHA nicht versioniert (Kalli-Muster).
SPM_DIR = $(APP).xcodeproj/project.xcworkspace/xcshareddata/swiftpm

gen: docs
	xcodegen generate
	@mkdir -p "$(SPM_DIR)"
	@cp Package.resolved "$(SPM_DIR)/Package.resolved"

# Nach einem bewussten Abhängigkeits-Update: Lockfile zurückschreiben.
lock:
	@cp "$(SPM_DIR)/Package.resolved" Package.resolved
	@git diff --stat Package.resolved

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) \
		-configuration $(CONFIG) -derivedDataPath $(DERIVED) \
		-onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO build

# MIT Signatur (wie Kalli): Der Test-Host ist die App selbst. Ad hoc signiert
# entstünde eine zweite Identität in den Bedienungshilfen-Einstellungen.
# Seam startet im Testlauf keine Beobachter (siehe SeamApp.isRunningTests).
test: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED) \
		-onlyUsePackageVersionsFromResolvedFile -allowProvisioningUpdates test

lint:
	@command -v swiftlint >/dev/null || { echo "swiftlint fehlt -> brew install swiftlint"; exit 1; }
	swiftlint lint --quiet --strict

# Testversion: bauen, mit Developer ID signierte KOPIE unter /tmp starten.
# Developer ID, damit die Bedienungshilfen-Freigabe über Builds hinweg hält.
dev:
	@bash scripts/dev-signed.sh

# lint zuerst: Ein Release mit Linter-Verstoß geht gar nicht erst los.
release: lint
	@bash scripts/release.sh

release-dry-run:
	@echo "VERSION:      $$(awk -F'\"' '/MARKETING_VERSION:/ { print $$2; exit }' project.yml)"
	@printf "DEVELOPER_ID: "; security find-identity -v -p codesigning | awk -F'\"' '/Developer ID Application/ { print $$2; exit }'
	@[ -z "$$(git status --porcelain)" ] && echo "Arbeitsbaum:  sauber" || echo "Arbeitsbaum:  NICHT sauber"

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj

# Testfassung lokal: signiert nach /Applications, Build-Nummer wie ein Release. Ohne Doku-Gate.
install:
	@sh scripts/install-signed.sh
