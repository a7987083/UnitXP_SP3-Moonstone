# v0.3.0 design notes

Based on the attached v0.2.1 recovery report: 785 groups total, 643 recovered, 142 dynamic-or-failed. The dominant failures are dynamic CALL/CLOSURE/GETTABLE, while several static chunks complete without TAB_* globals and therefore need generic/RETURN table export. v0.3.0 combines Bundle and phone FullSweep sources, deduplicates by decoded SHA256, preserves partial state, tolerates TAB row-width mismatches, and evaluates duplicate static variants.
