// Android-only: empty declarations of namespaces whose iOS declaration lives in a SwiftData or
// SwiftUI file, so their portable extensions (e.g. PrepositionService+Content.swift) still
// compile in DieKarteiCore. This folder holds real files, not links into the app; core_sync.py
// leaves it alone. Only ever add namespaces here, never behaviour.

enum PrepositionService {}
enum ClassTutorContext {}
