###  Wikiman Integration for Documentation and Wiki Lookup

The AI agent can use **Wikiman**, an offline search engine indexing the Gentoo Wiki, to retrieve context and follow-up details related to Gentoo installation, configuration, or troubleshooting.

#### Recommended Usage Flow:

1. **Trigger Wikiman Search**
   - When clarifying or refining any Gentoo guide step, run:
     ```bash
     wikiman -s gentoo -R <keywords>
     ```
     - `-s gentoo`: limit search to the Gentoo Wiki source.  
     - `-R`: enable raw output for easy parsing.

2. **Parse and Select Relevant Content**
   - The raw output includes lines formatted as:
     ```
     <Title>\t<Lang>\t<Source>\t<Path>
     ```
     - Choose the most relevant `<Title>` and then :
     ```bash
     w3m -dump "<Path>"
     ```
     - This extracts plain text for inclusion in the prompt context.

3. **Embed Context into Agent Prompt**
   - Prepend or append the extracted snippet into your AI prompt to ground the response in actual Gentoo documentation.

#### Example Workflow:
```bash
# Step 1: Search for "systemd-gpt-auto root"
wikiman -s gentoo -R systemd-gpt-auto root | head -n 5

# Suppose it gives:
# Discoverable Partitions Specification …\t/en\tgentoo\t/path/to/page

# Step 2: Render content
w3m -dump "/path/to/page" > context.txt

# Step 3: Use context.txt as context in your AI assistant
# Prompt example below
