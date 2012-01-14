#!/usr/bin/perl
$|=1;
use strictures 1;
use autodie;
use 5.10.0;
use Getopt::Long;

use lib 'lib';
use WhereTo;

## Setup, params:
my ($start_lat, $start_lon, $distance_mi, $start_ll, $circle_kml_fn, $allpoints_tsv_fn);
my $result = GetOptions("latitude=s" => \$start_lat,
                        "longitude=s" => \$start_lon,
                        "distance=s" => \$distance_mi,
                        "circle_kml:s" => \$circle_kml_fn,
                        "allpoints_tsv:s" => \$allpoints_tsv_fn
                       );
usage() if(!$start_lat || !$start_lon || !$distance_mi || !($circle_kml_fn || $allpoints_tsv_fn));
#51.58347,-1.77309

my $self = WhereTo->new();
$self->calculate_paths([$start_lat, $start_lon], $distance_mi);

if ($circle_kml_fn) {
  $self->write_kml([$start_lat, $start_lon], $circle_kml_fn);
}

if ($allpoints_tsv_fn) {
  $self->write_tsv($allpoints_tsv_fn);
}

sub usage {
  print "Usage: $0 --latitude 51.584483 --longitude -1.741585 --distance 1.75 (miles) --allpoints_tsv test.tsv\n";
  exit;
}
