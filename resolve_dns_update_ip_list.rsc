:local hosts {
    "example.com"
}

:local listName "unblocking"
:local commentPrefix "RKA"

# inspired by https://forum.mikrotik.com/viewtopic.php?t=58069#p297580

# test run: /system script run RosKomAround

:if ([:typeof [$ROSCOMAROUND]] = "nil") do={

    # block next run
    :global ROSCOMAROUND "starting..."; :put $ROSCOMAROUND

    :local timeStamp "$[/system clock get date] $[/system clock get time]"

    :foreach hostName in=$hosts do={

        :put ""

        :set ROSCOMAROUND "--- $hostName resolving..."; :put $ROSCOMAROUND

        # force dns entries to be cached
        :resolve $hostName

        :local dnsTree { $hostName }
        :local treePointer 0

        :while ($treePointer < [:len $dnsTree]) do={

            :set ROSCOMAROUND "[$treePointer] $($dnsTree->$treePointer)"; :put $ROSCOMAROUND

            :foreach recordDns in=[/ip dns cache all print as-value where (name=($dnsTree->$treePointer) && (type="CNAME" || type="A"))] do={
                :if ($recordDns->"type"="A") do={

                    :set ROSCOMAROUND "A: $($recordDns->"name") $($recordDns->"data")"; :put $ROSCOMAROUND

                    # upsert etnry
                    :local updateID [/ip firewall address-list find list=$listName address=($recordDns->"data")]
                    :if ([:len $updateID] = 0) do={
                        /ip firewall address-list add list=$listName address=($recordDns->"data") comment="$commentPrefix $hostName $timeStamp"
                    } else={
                        /ip firewall address-list set $updateID comment="$commentPrefix $hostName $timeStamp"
                    }
                }

                :if ($recordDns->"type"="CNAME") do={

                    :set ROSCOMAROUND "CNAME: $($recordDns->"name") $($recordDns->"data")"; :put $ROSCOMAROUND

                    :if ([:typeof [:find $dnsTree ($recordDns->"data")]] = "nil") do={
                        :set dnsTree ($dnsTree, $recordDns->"data")
                    } else={
                        :set ROSCOMAROUND "SKIPPING RECURSION"; :put $ROSCOMAROUND
                    }
                }

                # todo DNAME, ANAME ?
            }
            :set treePointer ($treePointer + 1)
        }

        # remove old entries
        :set ROSCOMAROUND "removing old entries: $commentPrefix $hostName"; :put $ROSCOMAROUND

        :foreach item in=[/ip firewall address-list print as-value where (list=$listName && comment~"^$commentPrefix $hostName " && comment~"^$commentPrefix $hostName $timeStamp\$"=false)] do={

            :set ROSCOMAROUND "- $($item->"address") $($item->"comment")"; :put $ROSCOMAROUND

            /ip firewall address-list remove ($item->".id")
        }

        :set ROSCOMAROUND "=== $([:tostr $dnsTree])"; :put $ROSCOMAROUND
    }

    # allow next run
    :set ROSCOMAROUND
}