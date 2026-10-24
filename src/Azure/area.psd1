# The Azure area: commands scoped to subscriptions and management groups.
@{
    Name        = 'Azure'
    Title       = 'Azure'
    Description = 'Commands for an Azure estate - subscriptions and management groups: inventory, cost, policy, governance, networking, security, identity in Azure (RBAC, managed identities), health, assessments, Terraform and deployment.'
    Order       = 1
    DependsOn   = @('Core')
}
