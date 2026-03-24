# TODOS

## P1 — High Priority

### Integration test infrastructure for ObjC++/Swift interop
- **Why:** Real bugs live at the ObjC++/Swift boundary (NSClassFromString, bridging headers, #if __has_include). Unit tests only cover pure Swift modules.
- **Effort:** M (CC: ~1 hour)
- **Context:** Outside voice in CEO review flagged this. All crashes in prior sessions were at interop boundaries (Onigmo, macOS 15+ NIB loading, value transformers).
- **Depends on:** Nothing

## P2 — Medium Priority

### Clean up dead Sources/SW3T* greenfield code
- **Why:** Two parallel codebases (Sources/ from abandoned greenfield, Frameworks/ from Strangler Fig) create confusion about which code is live.
- **Effort:** S (CC: ~5 min)
- **Context:** Outside voice in CEO review identified this as a maintenance trap.
- **Depends on:** Nothing
