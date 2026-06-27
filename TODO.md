# DockDock — TODO

## Bug da fixare

- [ ] **Spotify: controlli (play/pause/next/prev) restituiscono -1743** — Automation TCC non concessa per Spotify. L'utente deve concederla manualmente in Impostazioni di Sistema → Privacy → Automazione. Valutare se reinserire il pulsante "Grant Automation" in Settings (era stato rimosso).
- [ ] **Screen Recording thumbnails** — SCKit restituisce 0 finestre anche dopo grant. Richiede re-grant da Settings → Screen Recording dopo ogni rebuild; investigare se c'è un bug con il bundle ID durante lo sviluppo
- [x] **Finder: anteprime non appaiono** — fix verificato: SCKit con `onScreenWindowsOnly: false` e legacy con `.optionAll` mostrano correttamente 2-4 finestre Finder

## Migliorie UX

- [x] **Right-click Dock → chiudi panel** — panel DockDock si chiude quando si fa right-click su un'icona del Dock
- [x] **Multi-screen** — `isNearDock()` e `isDockAutoHidden()` ora usano lo schermo sotto il cursore invece di `NSScreen.main`
- [ ] **Tooltip nativo Dock** — il label dell'app name sotto l'icona si sovrappone al panel. Non esiste API pubblica per sopprimerlo; investigare se posizionare il panel per coprirlo o intercettare via CGEventTap
- [ ] **Chiudi panel su click thumbnail** — dopo aver cliccato su una finestra per portarla in foreground, chiudere automaticamente il preview panel
- [ ] **Tasto Escape** — premere Esc mentre si è sull'hover panel chiude il panel
- [ ] **Animazione resize panel Spotify** — transizione animata tra stato vuoto (72px) e player (370px) invece di jump istantaneo
- [ ] **Thumbnail placeholder** — mostrare skeleton grigio mentre SCKit cattura le finestre (invece di panel vuoto)
- [ ] **Spotify: stato loading** — aggiunto spinner "Loading…" mentre si aspetta il fetch AppleScript iniziale (150ms); da verificare in produzione

## Feature future

- [ ] **Azioni finestre** — hover su thumbnail mostra bottoni: Focus, Minimize, Close
- [ ] **Preferenza "Launch at Login"** — aggiungere toggle in Settings
- [ ] **Aggiungi supporto Music.app** — pannello simile a Spotify per Apple Music (AppleScript)
- [ ] **Prossimi eventi Calendar** — overlay calendario per l'icona Calendar.app nel Dock
- [ ] **Icona Dock custom** — quando l'app gira, icona nel Dock con badge (o solo menu bar)
- [ ] **Preview size dinamica** — thumbnail si adattano al numero di finestre (1 finestra → grande, molte → griglia compatta)
- [ ] **Auto-dismiss al click fuori** — panel si chiude se si clicca su qualcosa che non sia il panel o il Dock

## Release checklist

- [ ] Versione 0.1.0 stabile (firma Apple Development stabile)
- [ ] Repository GitHub privato aggiornato con tutte le modifiche della sessione
- [ ] CLAUDE.local.md aggiornato con note ambiente
- [ ] Testare su macOS Ventura 13.x (build target minimo)

## Processo di release

Ad ogni release:
1. Aggiornare `CFBundleShortVersionString` (semver: `1.2.3`) e `CFBundleVersion` (build incrementale) in `Info.plist`
2. Eseguire `bash make-release.sh` — fa build release + firma con Apple Development cert
3. Verificare firma: `codesign -dvvv /Applications/DockDock.app | grep TeamIdentifier`
4. Testare golden path: Accessibility, Screen Recording, Spotify hover
5. Committare e pushare → `git tag v0.x.0`
