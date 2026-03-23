# Cloud Provider Best Practices (AWS, Azure, GCP)

Each major cloud provider offers specific tools and strategies for cost management.

## AWS (Amazon Web Services)
- **Savings Plans:** Offer significant savings (up to 72%) on compute usage across EC2, Fargate, and Lambda in exchange for a commitment to a consistent amount of usage.
- **S3 Intelligent-Tiering:** Automatically moves data between access tiers when access patterns change, reducing storage costs without performance impact.
- **AWS Graviton:** Migrating to ARM-based Graviton instances often provides a 40% better price-performance ratio.
- **AWS Cost Explorer:** The native tool for visualizing and analyzing your AWS spend.

## Microsoft Azure
- **Azure Reservations:** Upfront commitment to resources for 1 or 3 years for significant discounts.
- **Azure Hybrid Benefit:** Use your on-premises Windows Server and SQL Server licenses with Software Assurance to save on Azure.
- **Spot Virtual Machines:** Access unused Azure compute capacity at deep discounts (up to 90%).
- **Azure Advisor:** Provides proactive, actionable, and personalized best practices for cost optimization.

## GCP (Google Cloud Platform)
- **Committed Use Discounts (CUDs):** Predictable discounts for a 1 or 3-year commitment to resources.
- **Custom Machine Types:** Unlike AWS/Azure, GCP allows you to specify exact CPU and RAM amounts, preventing waste from "stepping up" to a larger predefined instance size.
- **Cloud Storage Autoclass:** Automatically manages the lifecycle of your objects based on access patterns.
- **BigQuery Slots:** Switch from on-demand pricing to flat-rate (slots) for large, predictable data workloads.
