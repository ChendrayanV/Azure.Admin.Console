# Azure architecture icons

`Show-AACResourceMap` draws each resource with its official Azure icon.
`azure-icons.json` holds the icons it uses (97 of them) and the resource
types each one stands for (104).

- Source: Microsoft's Azure architecture icons, V21
  (https://learn.microsoft.com/azure/architecture/icons/), downloaded from
  https://arch-center.azureedge.net/icons/Azure_Public_Service_Icons_V21.zip
- The SVGs are unchanged, apart from the XML declaration being removed and
  the whitespace between tags being collapsed.
- SHA-256 of `azure-icons.json`: `85B824FD42006B89F35F6D832F763702F51393A94AC7A6B545EDA7798AEF91C1`

## Terms

From Microsoft's terms of use for the icons:

> Microsoft permits the use of these icons in architectural diagrams, training
> materials, or documentation. You may copy, distribute, and display the icons
> only for the permitted use unless granted explicit permission by Microsoft.
> Microsoft reserves all other rights.

The icons are used only to draw architecture diagrams of Azure resources, and
the map follows the icon guidelines:
- each icon is labelled with its product name;
- icons are never cropped, flipped, rotated or distorted;
- each icon stands only for the Azure product it was made for.

The icons are Microsoft's, not covered by this module's MIT licence.
