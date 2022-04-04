:local hosts {
    "example.com"
}

:local listName "unblocking"
:local commentPrefix "RKA"

# inspired by https://forum.mikrotik.com/viewtopic.php?t=58069#p297580

# test run: /system script run RosKomAround

:if ([:typeof [$ROSCOMAROUND]] = "nil") do={

    # block next run
    :global ROSCOMAROUND "starting..."; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

    :local timeStamp "$[/system clock get date] $[/system clock get time]"

    :foreach hostName in=$hosts do={

        :put ""

        :set ROSCOMAROUND "--- $hostName resolving..."; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

        # force dns entries to be cached
        :resolve $hostName

        :local dnsTree { $hostName }
        :local treePointer 0

        :while ($treePointer < [:len $dnsTree]) do={

            :set ROSCOMAROUND "[$treePointer] $($dnsTree->$treePointer)"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

            :foreach recordDns in=[/ip dns cache all print as-value where (name=($dnsTree->$treePointer) && (type="CNAME" || type="A"))] do={
                :if ($recordDns->"type"="A") do={

                    :set ROSCOMAROUND "A: $($recordDns->"name") $($recordDns->"data")"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

                    # upsert etnry
                    :local updateID [/ip firewall address-list find list=$listName address=($recordDns->"data")]
                    :if ([:len $updateID] = 0) do={
                        /ip firewall address-list add list=$listName address=($recordDns->"data") comment="$commentPrefix $hostName $timeStamp"
                    } else={
                        /ip firewall address-list set $updateID comment="$commentPrefix $hostName $timeStamp"
                    }
                }

                :if ($recordDns->"type"="CNAME") do={

                    :set ROSCOMAROUND "CNAME: $($recordDns->"name") $($recordDns->"data")"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

                    :if ([:typeof [:find $dnsTree ($recordDns->"data")]] = "nil") do={
                        :set dnsTree ($dnsTree, $recordDns->"data")
                    } else={
                        :set ROSCOMAROUND "SKIPPING RECURSION"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND
                    }
                }

                # todo DNAME, ANAME ?
            }
            :set treePointer ($treePointer + 1)
        }

        # remove old entries
        :set ROSCOMAROUND "removing old entries: $commentPrefix $hostName"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

        :foreach item in=[/ip firewall address-list print as-value where (list=$listName && comment~"^$commentPrefix $hostName " && comment~"^$commentPrefix $hostName $timeStamp\$"=false)] do={

            :set ROSCOMAROUND "- $($item->"address") $($item->"comment")"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

            /ip firewall address-list remove ($item->".id")
        }

        :set ROSCOMAROUND "=== $([:tostr $dnsTree])"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND
    }

    # allow next run
    :set ROSCOMAROUND
}