.PHONY: all analyze test run-android build-apk clean

all: analyze test

analyze:
	flutter analyze

test:
	flutter test --reporter expanded

run-android:
	flutter run -d ddb4c2bf

build-apk:
	flutter build apk --release
	flutter build apk --release --split-per-abi

clean:
	flutter clean
	flutter pub get
