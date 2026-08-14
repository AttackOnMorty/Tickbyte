# Hero price does not flash

A new print updates the number and leaves it full ink. Tape colour stays on the `%` only. We considered a 150ms last-print flash on the Hero price and rejected it — the tick is data arriving, not an interrupt, and a colour blink fights the “one full-ink number” rule.
