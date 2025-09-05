

### Wikiman Integration for Documentation and Wiki Lookup

The AI agent can use **Wikiman**, an offline search engine that indexes Gentoo Wiki snapshots, to retrieve context and follow up details related to Gentoo installation, configuration, or troubleshooting.

#### Installation and setup (one time)

```bash
# Install Wikiman (choose the command that matches your distro)
# Arch based
sudo pacman -S wikiman

# Debian or Ubuntu
sudo apt update && sudo apt install ./wikiman*.deb  # or install from your package manager

# Runtime dependencies
# man, fzf, ripgrep, awk, w3m, coreutils, parallel
# Example for Debian or Ubuntu:
sudo apt install -y man-db fzf ripgrep gawk w3m coreutils parallel
````

Fetch and enable the Gentoo Wiki source.

```bash
# Download the helper Makefile
curl -L 'https://raw.githubusercontent.com/filiparag/wikiman/master/Makefile' -o wikiman-makefile

# Fetch the Gentoo Wiki snapshot and install sources system wide
make -f ./wikiman-makefile source-gentoo
sudo make -f ./wikiman-makefile source-install

# Verify sources
wikiman -S  # should list "gentoo" with a path under /usr/share/doc/gentoo-wiki
```

#### Recommended usage flow

1. **Trigger a Wikiman search**

Run a raw search when clarifying or refining any Gentoo step.

```bash
wikiman -s gentoo -R <keywords>
```

Notes, `-s gentoo` limits the search to the Gentoo Wiki source. `-R` prints raw output for easy parsing. If the page title has uppercase letters, use the correct case (for example `Waybar`). For case-insensitive matching you can use a regex flag.

```bash
# case sensitive title search
wikiman -s gentoo -R Waybar

# case insensitive using a regex inline flag
wikiman -s gentoo -R '(?i)waybar'

# title only search (quick mode)
wikiman -s gentoo -q -R Waybar
```

2. **Parse and select relevant content**

Raw results are lines in this format.

```
<Title>\t<Lang>\t<Source>\t<Path>
```

Pick the best `<Title>`, then render the HTML to plain text for prompting.

```bash
w3m -dump "<Path>" > context.txt
```

3. **Embed context into the agent prompt**

Prepend or append the snippet from `context.txt` to ground the model’s answer in official documentation. Keep the snippet tight and relevant.

#### Example workflow

```bash
# Step 1: search for "systemd-gpt-auto root"
wikiman -s gentoo -R 'systemd-gpt-auto root' | head -n 5

# Suppose it returns a line like:
# Discoverable Partitions Specification\ten\tgentoo\t/usr/share/doc/gentoo-wiki/wiki/Discoverable_Partitions_Specification/en.html

# Step 2: render content to text
w3m -dump "/usr/share/doc/gentoo-wiki/wiki/Discoverable_Partitions_Specification/en.html" > context.txt

# Step 3: use context.txt as grounding input for your AI assistant
# Example prompt:
#   Use the following excerpt from the Gentoo Wiki as context, then answer my question about configuring systemd-gpt-auto for the root partition.
#   ---
#   $(cat context.txt)
#   ---
```

#### Troubleshooting tips

* Run `wikiman -S`. If `gentoo` is missing, rerun the source install commands above.
* Confirm the page exists in the snapshot.

  ```bash
  find /usr/share/doc/gentoo-wiki/wiki -iname 'waybar*' -printf '%p\n'
  rg -n --smart-case 'waybar' /usr/share/doc/gentoo-wiki/wiki | head
  ```
* If results look empty, check dependencies. You need `man`, `fzf`, `ripgrep`, `awk`, `w3m`, `coreutils`, `parallel`.
* For better matching inside the TUI, use lowercase queries. fzf uses smart case by default (lowercase is case insensitive, uppercase becomes case sensitive).

#### Notes for agent developers

* Prefer short queries, then filter with fzf if you are in interactive mode.
* For programmatic pipelines, always use `-R` and parse `\t` separated columns.
* Default HTML viewer is `w3m`. You can change it in `~/.config/wikiman/wikiman.conf` if needed.

```

Sources used for the guidelines above: Wikiman README and options, extra sources and Makefile usage, and the raw output schema.  fzf smart case behavior. :contentReference ripgrep case sensitivity and inline `(?i)` flag. w3m can typeset HTML to plain text. Arch manual page for wikiman that mentions installing sources with the Makefile.

If you want, I can also add a tiny helper script in the repo that wraps the search, picks the top match, and emits a trimmed `context.txt`.

```
