:local hosts {
    "example.com"
}

# keep old records for 7 days
:local keepOldSeconds (60 * 60 * 24 * 7)

# maintain address list
:local listName "unblocking"

# inspired by https://forum.mikrotik.com/viewtopic.php?t=58069#p297580

:global ROSCOMAROUND;

# test run: /system script run RosKomAround

# check variable exist
:if ([:typeof [$ROSCOMAROUND]] = "nil") do={
    :global ROSCOMAROUND "idle"
}

# https://forum.mikrotik.com/viewtopic.php?t=75555#p790745
:local EpochTime do={
    :local ds [:tostr $1]
    :local ts [:tostr $2]
    :local months
    :if ((([:pick $ds 9 11] - 1) / 4) != (([:pick $ds 9 11]) / 4)) do={
        :set months { "an"=0; "eb"=31; "ar"=60; "pr"=91; "ay"=121; "un"=152; "ul"=182; "ug"=213; "ep"=244; "ct"=274; "ov"=305; "ec"=335 }
    } else={
        :set months { "an"=0; "eb"=31; "ar"=59; "pr"=90; "ay"=120; "un"=151; "ul"=181; "ug"=212; "ep"=243; "ct"=273; "ov"=304; "ec"=334 }
    }
    :set ds (([:pick $ds 9 11] * 365) + (([:pick $ds 9 11] - 1) / 4) + ($months->[:pick $ds 1 3]) + [:pick $ds 4 6])
    :set ts (([:pick $ts 0 2] * 60 * 60) + ([:pick $ts 3 5] * 60) + [:pick $ts 6 8])
    :return ($ds * 24 * 60 * 60 + $ts + 946684800 - [/system clock get gmt-offset])
}

:if ($ROSCOMAROUND != "idle") do={
    # ignore concurrent run
    :local msg "already running"; :log debug $msg; :put $msg
} else={
    # concurrency lock
    :set ROSCOMAROUND "starting..."; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

    :local now [/system clock print as-value]
    :local timeStamp "$($now->"date") $($now->"time")"
    :local unixTime [$EpochTime ($now->"date") ($now->"time")]
    
    :foreach hostName in=$hosts do={

        :put ""
        :set ROSCOMAROUND "--- $hostName resolving..."; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

        # force dns entries to be cached
        :local resolved true
        :do { :resolve $hostName } on-error={ :set resolved false }

        :if ($resolved) do={

            :local dnsTree { $hostName }
            :local treePointer 0

            :while ($treePointer < [:len $dnsTree]) do={

                :set ROSCOMAROUND "[$treePointer] $($dnsTree->$treePointer)"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

                :foreach recordDns in=[/ip dns cache all print as-value where (name=($dnsTree->$treePointer) && (type="CNAME" || type="A"))] do={
                    :if ($recordDns->"type"="A") do={
                        :set ROSCOMAROUND "A: $($recordDns->"name") $($recordDns->"data")"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

                        :local comment "-- $unixTime -- $hostName -- $timeStamp"

                        # upsert etnry
                        :local updateID [/ip firewall address-list find list=$listName address=($recordDns->"data")]
                        :if ([:len $updateID] = 0) do={
                            :set ROSCOMAROUND "+ $($recordDns->"data") $comment"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND
                            /ip firewall address-list add list=$listName address=($recordDns->"data") comment=$comment
                        } else={
                            #:set ROSCOMAROUND "# $($recordDns->"data") $comment"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND
                            /ip firewall address-list set $updateID comment=$comment
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
            :set ROSCOMAROUND "old $hostName"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND

            :foreach item in=[/ip firewall address-list print as-value where (list=$listName && comment~"^-- [0-9]+ -- $hostName -- " && comment~"^-- $unixTime -- $hostName -- "=false)] do={
                :local oldUnixTime [:pick ($item->"comment") 3 [:find ($item->"comment") " -- " -1]]
                if (($unixTime - $oldUnixTime) > $keepOldSeconds) do={
                    :set ROSCOMAROUND "- $($item->"address") $($item->"comment")"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND
                    /ip firewall address-list remove ($item->".id")
                }
            }

            :set ROSCOMAROUND "=== $([:tostr $dnsTree])"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND
        } else={
            :set ROSCOMAROUND "--- $hostName resolution failed"; :log debug $ROSCOMAROUND; :put $ROSCOMAROUND
        }
    }

    # allow next run
    :set ROSCOMAROUND "idle"
}