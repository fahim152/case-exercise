var builder = WebApplication.CreateBuilder(args);
builder.Services.AddProblemDetails();
builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 16 * 1024);
var app = builder.Build();

app.UseExceptionHandler();
app.Use(async (context, next) =>
{
    // Fresh on every backend call; cached responses retain the earlier value.
    context.Response.Headers["X-Backend-Request-Id"] = Guid.NewGuid().ToString("N");
    await next(context);
});

app.MapGet("/products/{id}", IResult (string id) =>
    id is "1" or "2"
        ? Results.Ok(new { id, name = "Example Product", price = 100, currency = "DKK" })
        : Results.NotFound(new { error = "Product not found." }));

app.MapPost("/orders", IResult (CreateOrder request, HttpContext context) =>
{
    context.Response.Headers.CacheControl = "no-store";
    if (request.ProductId is not ("1" or "2") || request.Quantity is < 1 or > 1000)
        return Results.BadRequest(new { error = "Use productId 1 or 2 and an integer quantity from 1 to 1000." });

    // Demonstration response only: no order is created or stored.
    return Results.Json(new { orderId = "1", status = "created" }, statusCode: 201);
});

// Internal liveness check; not exposed by the gateway.
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.Run();

record CreateOrder(string? ProductId, int Quantity);
