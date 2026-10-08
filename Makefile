.PHONY: docs gen build test lint dev clean

APP = Seam
CONFIG ?= Debug
DERIVED = build

# CHANGELOG lebt im Repo-Wurzelverzeichnis und wird bei jedem Build ins Bundle
# gespiegelt (Kalli-Muster): Die App kann nie eine ältere Fassung anzeigen.
docs:
	cp CHANGELOG.md Seam/Resources/CHANGELOG.md

gen: docs
	xcodegen generate

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) \
		-configuration $(CONFIG) -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build

# MIT Signatur (wie Kalli): Der Test-Host ist die App selbst. Ad hoc signiert
# entstünde eine zweite Identität in den Bedienungshilfen-Einstellungen.
# Seam startet im Testlauf keine Beobachter (siehe SeamApp.isRunningTests).
test: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED) \
		-allowProvisioningUpdates test

lint:
	@command -v swiftlint >/dev/null || { echo "swiftlint fehlt -> brew install swiftlint"; exit 1; }
	swiftlint lint --quiet --strict

# Testversion: bauen, mit Developer ID signierte KOPIE unter /tmp starten.
# Developer ID, damit die Bedienungshilfen-Freigabe über Builds hinweg hält.
dev:
	@bash scripts/dev-signed.sh

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj
