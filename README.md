# JobGuardian AI

AI-powered SQL Server Agent job monitoring and remediation using .NET 10, Azure OpenAI, and Data API Builder (DAB).

---

## Prerequisites

- [.NET 10 SDK](https://dotnet.microsoft.com/download)
- SQL Server or [SQL Server Express LocalDB](https://learn.microsoft.com/sql/database-engine/configure-windows/sql-server-express-localdb)
- [Data API Builder CLI](https://learn.microsoft.com/azure/data-api-builder/get-started/get-started-with-data-api-builder) — install once:
  ```bash
  dotnet tool install --global Microsoft.DataApiBuilder
  ```
- Azure OpenAI resource with a `gpt-4o-mini` deployment

---

## Database Setup

1. Open SQL Server Management Studio (or `sqlcmd`) and run the script:

   ```
   McpMaverick\DatabaseScripts\JobExecutionStatus.sql
   ```

   This script:
   - Creates the **`JobGuardianAI`** database (if it doesn't already exist)
   - Creates the **`dbo.JobStatus`** view — reads live SQL Agent job history from `msdb`
   - Creates the **`dbo.KnowledgeBase`** table — maps error patterns to root causes and remediation actions, seeded with 8 common failure types
   - Creates the **`dbo.ActionHistory`** table — audit log of every remediation action taken by the AI

---

## Data API Builder (DAB) Configuration

DAB exposes the database resources as a REST/GraphQL API consumed by the app.

### 1. Initialize DAB

From the repo root (or any working directory), run:

```bash
dab init --database-type "mssql" --host-mode "Development" --connection-string "Server=(localdb)\MSSQLLocalDB;Database=JobGuardianAI;Trusted_Connection=True;TrustServerCertificate=true;"
```

This creates a `dab-config.json` file in the current directory.

### 2. Add the database resources

Add the **`JobStatus`** view (read-only):

```bash
dab add JobStatus --source "dbo.JobStatus" --source.type "view" --source.key-fields "JobId" --permissions "anonymous:read"
```

Add the **`KnowledgeBase`** table:

```bash
dab add KnowledgeBase --source "dbo.KnowledgeBase" --source.type "table" --permissions "anonymous:*"
```

Add the **`ActionHistory`** table:

```bash
dab add ActionHistory --source "dbo.ActionHistory" --source.type "table" --permissions "anonymous:*"
```

### 3. Start the DAB server

```bash
dab start
```

By default the API is available at `https://localhost:5001` (REST) and `https://localhost:5001/graphql` (GraphQL).

---

## Application Configuration

Update `McpMaverick\src\appsettings.json` (or `appsettings.Development.json`) with your connection string and Azure OpenAI details:

```json
{
  "ConnectionStrings": {
	"SqlServer": "Server=(localdb)\\MSSQLLocalDB;Database=JobGuardianAI;Trusted_Connection=True;TrustServerCertificate=true;"
  }
}
```

In `Program.cs`, replace the placeholder values with your Azure OpenAI endpoint and key:

```csharp
var client = new AzureOpenAIClient(
	new Uri("<your-azure-openai-endpoint>"),
	new AzureKeyCredential("<your-api-key>"));
```

---

## Running the Application

```bash
cd McpMaverick\src
dotnet run
```

Navigate to `https://localhost:<port>` to open the Job Guardian AI dashboard.
