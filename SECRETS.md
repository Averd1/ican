# Secrets Management

## API Key Injection

The Gemini API key is injected at **compile time** via Dart's `--dart-define` flag.
It is read in code as `const String.fromEnvironment('API_KEY')`.

### Running locally

```bash
flutter run --dart-define=API_KEY=<your-gemini-api-key>
```

### Building for release

```bash
flutter build ios --dart-define=API_KEY=<your-gemini-api-key>
flutter build apk --dart-define=API_KEY=<your-gemini-api-key>
```

### Generating a key

Create or rotate your key at https://aistudio.google.com/apikey

## Rules

- **`.env` must never be committed.** It is in `.gitignore` for local convenience only.
- Do not hardcode API keys anywhere in source files.
- For CI/CD, store the key as a secret environment variable and pass it via `--dart-define`.
