# GEMINI.md - FinOps & AI Workflow Mandates

This file contains foundational mandates for all work within the `ai-terminal-workflow` directory. These instructions take precedence over general defaults.

## 1. FinOps Strategy & Cost Awareness
- **Shift-Left Costing:** Every architectural or code change must be evaluated for its cost impact before implementation.
- **Resource Lifecycle:** All test resources must include an explicit expiration or cleanup strategy (e.g., auto-delete tags).
- **Unit Economics:** Prioritize measuring value-per-dollar over absolute spend.

## 2. Engineering Standards
- **Documentation First:** Major architectural decisions and cost-optimization strategies must be documented in a README.md within the relevant sub-project folder.
- **Automated Validation:** Use tools like `infracost` or `terraform plan` to validate cost implications during the strategy phase.
- **Clean Abstractions:** Avoid hardcoding cloud-specific service names; use environment variables or configuration files for resource identifiers.

## 3. Study & Research Goals
- **Evidence-Based Learning:** When researching tools, prioritize empirical data and community-backed open-source projects (CNCF projects are preferred).
- **Iterative Improvement:** Regularly revisit the `cost_optimization` and `best_practices` guides as cloud provider features evolve.
