DEVICE ?= ddb4c2bf

.PHONY: all analyze test run-android build-apk clean

all: analyze test

analyze:
	flutter analyze

test:
	flutter test --reporter expanded

run-android:
	flutter run -d $(DEVICE)

build-apk:
	flutter build apk --release

clean:
	flutter clean
	flutter pub get
