FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /build
COPY NuGet.Config ./
COPY src/backend/ ./
RUN dotnet publish ProductOrder.Api.csproj -c Release -o /out

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /out/ ./
ENV ASPNETCORE_HTTP_PORTS=8080 \
    ASPNETCORE_ENVIRONMENT=Production
USER app
EXPOSE 8080
HEALTHCHECK --interval=5s --timeout=3s --start-period=20s --retries=12 \
    CMD curl --fail --silent http://127.0.0.1:8080/health > /dev/null || exit 1
ENTRYPOINT ["dotnet", "ProductOrder.Api.dll"]
