FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY CopCarPasseyApi.csproj .
RUN dotnet restore

COPY . .
RUN dotnet publish -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

# Create a non-root user
RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

COPY --from=build /app/publish .

# SQLite database lives in a mounted volume in production
VOLUME ["/app/data"]
ENV ConnectionStrings__Default="Data Source=/app/data/passkey.db"

EXPOSE 8080
ENTRYPOINT ["dotnet", "CopCarPasseyApi.dll"]
