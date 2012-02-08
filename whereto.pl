#!/usr/bin/env perl

use strict;
use warnings;

use Web::Simple 'WhereTo::Web';
use lib '/mnt/shared/projects/geo/osm/whereto/lib';
use WhereTo;

{
    package WhereTo::Web;

    sub dispatch_request {

        my $filedir = '/mnt/shared/projects/geo/osm/whereto/data-files/';
        sub (GET + ?latitude=&longitude=&distance=) {
            my ($self, $lat, $lon, $dist) = @_;
            ## Would be handy if we could also take a postcode/address.

            ## Should possibly test the params better:
            die "No such Latitude: $lat" if ($lat !~ /^[-\d\.]+[NS]?$/);
            die "No such Latitude: $lon" if ($lon !~ /^[-\d\.]+[WE]?$/);
            die "Impossible distance $dist" if($dist !~ /^[\d\.]+$/);

            ## Avoid running twice for same inputs:
            my $tsv_file = "${filedir}${lat}x${lon}x${dist}.tsv";
            if(-e $tsv_file) {
                $tsv_file =~ s{/mnt/shared/projects/geo/osm/whereto/}{};
                return [200, [ 'Content-type', 'text/plain' ], [ $tsv_file || '' ] ];
            }

            my $whereto = WhereTo->new();
            $whereto->calculate_paths([$lat, $lon], $dist);
            die "No paths found" if(!@{$whereto->{terminals}});

            $whereto->write_tsv($tsv_file);
            $tsv_file =~ s{/mnt/shared/projects/geo/osm/whereto/}{};

            return [200, [ 'Content-type', 'text/plain' ], [ $tsv_file || '' ] ];
            
        }
    }
}


WhereTo::Web->run_if_script;

