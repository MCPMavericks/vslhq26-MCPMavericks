using Azure;
using Azure.AI.OpenAI;

using McpMaverick.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddRazorPages();
builder.Services.AddHttpClient<SqlJobService>(client =>
{
    var baseUrl = builder.Configuration["DabBaseUrl"]
        ?? throw new InvalidOperationException("'DabBaseUrl' is not configured.");
    client.BaseAddress = new Uri(baseUrl);
});

//builder.Services.AddSingleton(sp =>
//{
//    var client = new AzureOpenAIClient(
//        new Uri("LLM URL from Open ai foundry"),
//        new AzureKeyCredential("Key"));

//    return client.GetChatClient("gpt-4o-mini");
//});

builder.Services.AddRazorPages(options =>
{
    options.Conventions.AddPageRoute("/Jobs", "");
});
var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();

app.UseRouting();

app.UseAuthorization();

app.MapStaticAssets();
app.MapRazorPages()
   .WithStaticAssets();

app.Run();
