# GEM-LLM documentation Makefile
# ----------------------------------------------------------------------------
# All real work is delegated to scripts/build-docs.sh; targets here are thin
# wrappers so that `make book-ko`, `make all`, etc. behave intuitively.
#
# Usage:
#   make book-ko         # PDF + DOCX + TEX + MD for the Korean book
#   make all             # every target × every format
#   make clean           # move docs/build/out to _trash/build-out-<ts>
#   make diagrams        # only render mermaid -> SVG
#   make watch TARGET=book-ko   # rebuild on change (requires entr)
#   make doctor          # check toolchain (pandoc, xelatex, mmdc, fonts)

ROOT        := $(CURDIR)
SCRIPTS_DIR := $(ROOT)/scripts
BUILD_DIR   := $(ROOT)/docs/build
OUT_DIR     := $(BUILD_DIR)/out
TRASH_DIR   := $(ROOT)/_trash
TS          := $(shell date +%Y%m%d-%H%M%S)

BUILD       := $(SCRIPTS_DIR)/build-docs.sh

.PHONY: all book-ko book-en manual-ko manual-en paper-ko paper-en \
        diagrams clean doctor watch help

help:
	@echo "Targets:"
	@echo "  book-ko / book-en       Korean / English book (md+tex+docx+pdf)"
	@echo "  manual-ko / manual-en   Operator manual"
	@echo "  paper-ko / paper-en     Paper (KCI / IEEEtran)"
	@echo "  all                     Every target above"
	@echo "  diagrams                Render mermaid -> SVG"
	@echo "  clean                   Move docs/build/out to _trash (no rm)"
	@echo "  doctor                  Toolchain prerequisite check"
	@echo "  watch TARGET=book-ko    Rebuild on change (needs entr)"

book-ko:
	$(BUILD) book-ko all

book-en:
	$(BUILD) book-en all

manual-ko:
	$(BUILD) manual-ko all

manual-en:
	$(BUILD) manual-en all

paper-ko:
	$(BUILD) paper-ko all

paper-en:
	$(BUILD) paper-en all

all: book-ko book-en manual-ko manual-en paper-ko paper-en

diagrams:
	$(SCRIPTS_DIR)/build-diagrams.sh

# clean = MOVE outputs to _trash; never `rm -rf`.
clean:
	@mkdir -p $(TRASH_DIR)
	@if [ -d $(OUT_DIR) ]; then \
		mv $(OUT_DIR) $(TRASH_DIR)/build-out-$(TS); \
		echo "[make clean] moved $(OUT_DIR) -> $(TRASH_DIR)/build-out-$(TS)"; \
	else \
		echo "[make clean] $(OUT_DIR) does not exist; nothing to do"; \
	fi
	@mkdir -p $(OUT_DIR)

doctor:
	@echo "== pandoc =="    && pandoc --version | head -1 || echo "MISSING"
	@echo "== xelatex =="   && xelatex --version | head -1 || echo "MISSING"
	@echo "== mmdc =="      && (mmdc --version 2>/dev/null | head -1 || echo "MISSING (npm install -g @mermaid-js/mermaid-cli)")
	@echo "== node =="      && (node --version 2>/dev/null || echo "MISSING")
	@echo "== Korean fonts ==" && fc-list :lang=ko | head -3 || echo "MISSING (apt install fonts-noto-cjk)"

# Auto-rebuild loop. Requires `entr` (apt install entr) or falls back to a
# message instructing the user how to install it.
watch:
	@if ! command -v entr >/dev/null 2>&1; then \
		echo "[watch] 'entr' is not installed."; \
		echo "[watch] sudo apt install entr   # Debian/Ubuntu"; \
		echo "[watch] alternative: install inotify-tools and run a manual loop."; \
		exit 1; \
	fi
	@if [ -z "$(TARGET)" ]; then echo "[watch] usage: make watch TARGET=book-ko"; exit 2; fi
	@find $(ROOT)/docs/$(TARGET) -name '*.md' | entr -c -- $(BUILD) $(TARGET) pdf
