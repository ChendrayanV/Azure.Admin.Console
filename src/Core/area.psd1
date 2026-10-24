# The Core area: what every other area builds on - signing in (Connect-AAC), the
# REST layer (HTTP, tokens, Resource Manager, Resource Graph, Microsoft Graph),
# the progress display, the console views and the CSV, HTML and PDF reports.
@{
    Name        = 'Core'
    Title       = 'Core: sign-in, REST and reports'
    Description = 'Signing in to Azure, the REST helpers every command uses (Resource Manager, Resource Graph, Microsoft Graph), the console views and the CSV, HTML and PDF reports.'
    Order       = 0
    DependsOn   = @()
}
