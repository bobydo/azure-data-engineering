# Synapse

Synapse Studio artifacts (SQL scripts, notebooks) are saved here via Git integration.

**Configure Git integration:**  
Synapse Studio → Manage → Source control → Git configuration  
- Collaboration branch: `main`  
- Root folder: `/synapse`

**Publish behaviour (same pattern as ADF):**  
- Saving in Studio → commits to `main`  
- Publish All → deploys to live workspace + pushes ARM template to `workspace_publish` branch
