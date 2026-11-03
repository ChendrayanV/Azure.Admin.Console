# IP address management

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACIPAMReport`](../Get-AACIPAMReport.md)

`Get-AACIPAMReport` is IP address management without a server: no app to
deploy, no database to drift. Every run measures Azure's address space, read
from Azure Resource Graph, against your address plan.

```powershell
Get-AACIPAMReport -Open                                              # every network vs the private ranges, in your browser
Get-AACIPAMReport -AddressPlan .\ipam-plan.psd1 -HtmlPath .\IPAM.html -PdfPath .\IPAM.pdf
Get-AACIPAMReport -AddressPlan .\ipam-plan.psd1 -NextAvailable 24, 22 -View NextAvailable -NoDisplay
Get-AACIPAMReport -TestCidr 10.20.8.0/22                             # free? if not, who has it
Get-AACIPAMReport -ManagementGroupId mg-landingzones -View IpAddress -CsvPath .\ips.csv
```

The address plan is a `.psd1`, `.json` or `.csv` file (or a hashtable): spaces
holding blocks, plus external ranges (on-premises, partners) Azure must not
overlap. Without one, the private ranges (RFC 1918 and RFC 6598) are the plan.

```powershell
@{ Spaces = @(
    @{ Name = 'Corp'; Blocks = @(
        @{ Name = 'Azure-EU'; Cidr = '10.20.0.0/14' }
        @{ Name = 'Azure-US'; Cidr = '10.24.0.0/14' } ) } )
   External = @( @{ Name = 'London DC'; Cidr = '10.0.0.0/16' } ) }
```

- **Blocks:** the networks in each, the address space they take (overlaps
  counted once), free space, the largest free range, the next free range of
  the first `-NextAvailable` size and how many still fit; Warning at
  `-WarningPercent` (80), Critical at `-CriticalPercent` (90), Full.
- **Networks:** virtual networks, Virtual WAN hubs and external ranges -
  Managed, Partly managed or Unmanaged - with subnets, addresses used, address
  space in no subnet, DNS servers, peerings, overlaps and the Azure IPAM
  reservation tag (`X-IPAM-RES-ID`).
- **Subnets and IP addresses:** every address Azure counts in a subnet -
  virtual machines, scale set instances, private endpoints, load balancers,
  firewalls, gateways, Bastion, application gateways and unattached network
  interfaces - so a subnet's count and its list always agree.
- **Overlaps:** High when the networks are peered, Medium with an external
  range or a hub, Low when isolated.
- **Free space:** the best fit (the smallest free range a size fits, keeping
  larger ranges whole) and the lowest free address, and every free range.
- **HTML report:** a tab for each, the plan as a tree (space > block > network
  > subnet), a Space selector that filters every tab, and a card that follows
  the pointer over a row with its details.

It reads; it doesn't hand out reservations. For that, Azure IPAM keeps the
shared state; this report checks Azure against any plan, Azure IPAM's
included.
