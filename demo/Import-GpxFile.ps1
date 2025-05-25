function Import-GpxFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string[]]$Path,
        [switch]$EnableException
    )

    foreach ($file in Get-ChildItem -Path $Path) {
        try {
            $gpx = ([xml](Get-Content -Path $file.FullName)).gpx
            foreach ($track in $gpx.trk) {
                $segments = foreach ($segment in $track.trkseg) {
                    $points = foreach ($point in $segment.trkpt) {
                        $point.lon + ' ' + $point.lat
                    }
                    if ($points.Count -gt 1) {
                        '(' + ($points -join ',') + ')'
                    }
                }
                if ($segments.Count -gt 1) {
                    $wkt = 'MULTILINESTRING (' + ($segments -join ',') + ')'
                } elseif ($segments.Count -eq 1) {
                    $wkt = 'LINESTRING ' + $segments
                } else {
                    $wkt = ''
                }
                $name = $track.name
                if ($name.'#cdata-section') {
                    $name = $name.'#cdata-section'
                }
                [PSCustomObject]@{
                    type = 'Track'
                    name = $name
                    wkt  = $wkt
                }
            }
            foreach ($route in $gpx.rte) {
                $points = foreach ($point in $route.rtept) {
                    $point.lon + ' ' + $point.lat
                }
                if ($points.Count -gt 1) {
                    $wkt = 'LINESTRING (' + ($points -join ',') + ')'
                } else {
                    $wkt = ''
                }
                $name = $route.name
                if ($name.'#cdata-section') {
                    $name = $name.'#cdata-section'
                }
                [PSCustomObject]@{
                    type = 'Route'
                    name = $name
                    wkt  = $wkt
                }
            }
            foreach ($waypoint in $gpx.wpt) {
                $wkt = 'POINT (' + $waypoint.lon + ' ' + $waypoint.lat + ')'
                $name = $waypoint.name
                if ($name.'#cdata-section') {
                    $name = $name.'#cdata-section'
                }
                [PSCustomObject]@{
                    type = 'Waypoint'
                    name = $name
                    wkt  = $wkt
                }
            }
        } catch {
            Stop-PSFFunction -Message "Import of [$($file.FullName)] failed: $($_.Exception.Message)" -Target $file -EnableException $EnableException -Continue
        }
    }
}
