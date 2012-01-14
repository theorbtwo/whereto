#!/usr/bin/perl
$|=1;
use strictures 1;
use autodie;
use 5.10.0;
use Geo::Ellipsoid;
use LWP::Simple 'get';
use Geo::Parse::OSM::Multipass;
use Getopt::Long;
use Data::Dump::Streamer 'Dump', 'Dumper';
use Imager;

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

my $self = bless {}, __PACKAGE__;
$self->main([$start_lat, $start_lon], $distance_mi);

if ($circle_kml_fn) {
  $self->write_kml([$start_lat, $start_lon], $circle_kml_fn);
}

if ($allpoints_tsv_fn) {
  $self->write_tsv($allpoints_tsv_fn);
}

sub filter_node {
  my ($self, $node) = @_;
  
  #print "Filtering node: $node\n";
  #Dump $node;

  # No links -- it's a PoI, not a part of a way.
  return 0 if !$node->{links} or !@{$node->{links}};

  # If any of the potential links are something that we can walk on, keep the node.
  for my $link (@{$node->{links}}) {
    return 1 if $self->filter_link($link);
  }

  return 0;
}

sub filter_link {
  my ($self, $link) = @_;

  return 1 if (($link->[0]{tag}{foot}||'x') ~~ [qw<yes>]);

  return 0 if $link->[0]{tag}{proposed};

  #print "Filtering link:\n";
  #print "From ", join(" // ", map {$_//"undef"} caller(0)), "\n";
  #Dump $link;
  # Big roads that you shouldn't walk on.
  return 0 if ($link->[0]{tag}{highway}||'x') ~~ ['trunk', 'trunk_link'];
  
  # Things that you can't walk through.
  return 0 if ($link->[0]{tag}{barrier}||'x') ~~ ['hedge', 'wall'];
  if ($link->[0]{tag}{barrier}) {
    print "Barrier: ", $link->[0]{tag}{barrier}, "\n";
  }
  
  return 0 if (($link->[0]{tag}{railway}||'x') ~~ [qw<rail platform>]);

  # I'd like to exclude all areas, but there's not really a good mechanical way to do that presently.
  # All valid areas will have a $link->[0]{outer}, but that's also true of any circular feature -- such as a roundabout.
  return 0 if $link->[0]{tag}{amenity};
  return 0 if $link->[0]{tag}{landuse};
  return 0 if (($link->[0]{tag}{leisure}||'x') ~~ [qw<park playground pitch>]);
  return 0 if $link->[0]{tag}{building};
  return 0 if $link->[0]{tag}{boundary};

  return 1;
}

sub earth {
  state $earth;
  if (!$earth) {
    $earth = Geo::Ellipsoid->new(ell => 'WGS84',
                                 units => 'degrees',
                                 distance_units => 'miles',
                                 # 1 -- symmetric -- -180..180
                                 longitude => 1,
                                 bearing => 1,
                                );
  }
  
  return $earth;
}

sub write_tsv {
  my ($self, $fn) = @_;
  
  my $earth = $self->earth;

  open my $fh, ">", $fn;
  
  print $fh join("\t", qw<lat lon title description>), "\n";
  for my $path (sort {$a->{pathlen} <=> $b->{pathlen}} values %{$self->{seen}}) {
    my $end_node = $path->{path}[-1]{node};
    
    my $desc;
    my $prev_node;
    my $prev_way;
    for my $pathelem (@{$path->{path}}) {
      if (not defined $pathelem->{way}) {
        # The initial point
        $desc .= "START<br/>";
      } else {
        my $bearing = $earth->bearing($prev_node->{lat}, $prev_node->{lon},
                                      $pathelem->{node}{lat}, $pathelem->{node}{lon});
        my $bearing_word;

        if ($bearing < -135) {
          $bearing_word = 'south';
        } elsif ($bearing < -45) {
          $bearing_word = 'west';
        } elsif ($bearing < 45) {
          $bearing_word = 'north';
        } elsif ($bearing < 135) {
          $bearing_word = 'east';
        } else {
          $bearing_word = 'south';
        }

        my $waydesc;
        my $highway = $pathelem->{way}{tag}{highway} // 'undef';

        if (exists $pathelem->{way}{tag}{name}) {
          $waydesc = $pathelem->{way}{tag}{name};
        } elsif ($pathelem->{way}{tag}{ref}) {
          $waydesc = 'the '.$pathelem->{way}{tag}{ref};
        } elsif (($pathelem->{way}{tag}{junction}||'x') eq 'roundabout') {
          $waydesc = 'the roundabout';
        } elsif ($highway eq 'path') {
          $waydesc = 'a generic path';
        } elsif ($highway eq 'primary') {
          $waydesc = 'a major road';
        } elsif ($highway eq 'primary_link') {
          $waydesc = 'the link to a major road';
        } elsif ($highway eq 'steps') {
          $waydesc = 'some stairs';
        } elsif ($highway eq 'secondary') {
          $waydesc = 'a midsized road';
        } elsif ($highway eq 'tertiary_link') {
          $waydesc = 'the link to a small road';
        } elsif ($highway eq 'tertiary') {
          $waydesc = 'a small road';
        } elsif ($highway eq 'unclassified') {
          $waydesc = 'a tiny road';
        } elsif ($highway eq 'track') {
          $waydesc = 'a track';
        } elsif ($highway eq 'residential') {
          $waydesc = 'a residential street';
        } elsif ($highway eq 'cycleway') {
          $waydesc = 'a cycle path';
        } elsif ($highway eq 'service') {
          $waydesc = 'an access road';
        } elsif ($highway eq 'road') {
          $waydesc = "some sort of road";
        } elsif (($pathelem->{way}{tag}{amenity} || 'x') eq 'parking') {
          $waydesc = 'a parking lot';
        } elsif (not keys %{$pathelem->{way}{tag}}) {
          $waydesc = '???';
        } elsif (($pathelem->{way}{tag}{railway} || "x") eq 'disused') {
          $waydesc = 'a disused rail track';
        } elsif (($pathelem->{way}{tag}{waterway}||'x') eq 'river') {
          $waydesc = 'a river';
        } elsif (($pathelem->{way}{tag}{waterway}||'x') eq 'stream') {
          $waydesc = 'a stream';
        } elsif ($highway eq 'footway') {
          $waydesc = 'a footpath';
        } else {
          Dump $pathelem;
          die "Don't know how to describe this way";
        }

        if ($pathelem->{way}{tag}{bridge}) {
          $waydesc .= " bridge";
        }

        $desc .= "go $bearing_word on $waydesc<br/>";
      }

      $prev_node = $pathelem->{node};
      $prev_way = $pathelem->{way};
    }
    
    print $fh join("\t", $end_node->{lat}, $end_node->{lon}, $path->{pathlen}, $desc), "\n";
  }
}

sub usage {
  print "Usage: $0 --latitude 51.584483 --longitude -1.741585 --distance 1.75 (miles)\n";
  exit;
}

sub get_region {
  my ($self, $center, $radius) = @_;

  my $earth = $self->earth;
  my ($north, $west) = $earth->at(@$center, $radius, 315);
  my ($south, $east) = $earth->at(@$center, $radius, 135);

  printf "North:  %f\n", $north;
  printf "Center: %f\n", $center->[0];
  printf "South:  %f\n", $south;

  printf "West:   %f\n", $west;
  printf "Center: %f\n", $center->[1];
  printf "East:   %f\n", $east;

  my $url = 'http://api.openstreetmap.org/api/0.6/map?bbox='.join(',', $west, $south, $east, $north);
  print "Fetching $url\n";

  my $xml = get($url);
  #print $xml, "\n\n";

  #my $xml = 'map?bbox=-1.77032811520983,51.5665801990025,-1.71286446285378,51.6023787132927';

  my $parser = Geo::Parse::OSM::Multipass->new(\$xml,
                                               pass2 => sub {$self->pass2(@_)},
                                              );

  $parser->parse(sub {});

  return $self;
}

sub pass2 {
  my ($self, $bit, $parser) = @_;

  $bit = {%$bit};

  #Dump $bit;

  given ($bit->{type}) {
    when ('bound') {
      push @{$self->{known}}, $bit;
    };

    when ('node') {
      $self->{nodes}{$bit->{id}} = $bit;
    };

    when ('way') {
      my @nodes = @{$bit->{chain}};

      for my $i (0..@nodes-1) {
        my $prev_id = $i>0 ? $nodes[$i-1] : undef;
        my $this_id = $nodes[$i];
        my $next_id = $i<@nodes-1 ? $nodes[$i+1] : undef;

        push @{$self->{nodes}{$this_id}{links}}, [$bit, $prev_id] if $prev_id;
        push @{$self->{nodes}{$this_id}{links}}, [$bit, $next_id] if $next_id;
      }
    };

    when ('relation') {
      # Do nothing?
    }

    default {
      Dump $bit;
      die "Don't know how to deal with osm bit";
    };
  }
}

sub find_nearest_node {
  my ($self, $ll) = @_;

  my $earth = $self->earth;

  my ($best_dist, $best_node) = (9e999, undef);
  for my $node (values %{$self->{nodes}}) {
    next if !$self->filter_node($node);

    my $dist = $earth->range(@$ll, $node->{lat}, $node->{lon});
    if ($best_dist > $dist) {
      $best_dist = $dist;
      $best_node = $node;
    }
  }

  print "find_nearest_node: best node was $best_dist miles away\n";
  return $best_node;
}


sub main {
    my ($self, $start_ll, $target_len, $filename) = @_;
#    my $start_ll = [51.584483, -1.741585];
#    my $target_len = 1.75;
    $self->get_region($start_ll, $target_len);

    my $start = $self->find_nearest_node($start_ll);
    Dump $start;


    my $earth = $self->earth;
    my @frontier = (
        {path => [{
                   node => $start,
                   way => undef,
                  }],
         # Length, in miles, of the current path.
         pathlen => 0
        }
        );
    my %seen;
    my $longest_path = {pathlen => 0};
    my @terminals;

    while (@frontier) {
        # Would using min_index from List::Utils be more efficent?  Quite possibly, or use an insertion sort when adding new nodes.
        @frontier = sort {$a->{pathlen} <=> $b->{pathlen}} @frontier;
        my $this_path = shift @frontier;
        my $here = $this_path->{path}[-1]{node};

        #print $this_path->{pathlen}, ": ", join(", ", map {$_->{node}{id}} @{$this_path->{path}}), "\n";

        if (exists $seen{$here->{id}}) {
            if ($seen{$here->{id}}{pathlen} > $this_path->{pathlen}) {
                print "Hmm, found a shorter path later?  Shouldn't happen.\n";
            }
            next;
        }

        $seen{$here->{id}} = $this_path;

        if ($this_path->{pathlen} > $longest_path->{pathlen}) {
            $longest_path = $this_path;
        }

        for my $link (@{$here->{links}}) {
            next unless $self->filter_link($link);

            my $new_node = $self->{nodes}{$link->[1]};

            my $new_path_elem = {
                                 node => $new_node,
                                 way  => $link->[0]
                                };
            my $new_len = $earth->range($here->{lat}, $here->{lon}, $new_node->{lat}, $new_node->{lon});
            my $new_path = {
                            path => [
                                     @{$this_path->{path}},
                                     $new_path_elem
                                    ],
                            pathlen => $this_path->{pathlen} + $new_len
            };

            # Exit condition: stop paths when they get longer then a mile.
            if ($new_path->{pathlen} >= $target_len) {
                #Dump $new_path;
                push @terminals, $new_node;
                #print "Found path over a mile:\n";
                #print Dumper $new_path;
            } else {
                push @frontier, $new_path;
            }
        }

        if (not @{$here->{links}}) {
            # Hmm.  This is the presumable cause of "gaps" in the outer rim.  OTOH, putting in all of these will make it no longer a rim so much as a bunch of dead ends.
            # I see no clear way of fixing this outside of completely revamping the UI... which I planned to do anyway.
        }
    }

#print "Longest path found: \n";
#print Dumper $longest_path;

    $self->{terminals} = \@terminals;
    $self->{seen} = \%seen;
}

sub write_kml {
    my ($self, $start_ll, $terminals, $filename) = @_;

    $terminals = $self->terminals;

    open my $kml_out, '>', $filename;

    print $kml_out <<"END";
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Paths</name>
    <Style id="yellowLineGreenPoly">
      <LineStyle>
        <color>99ffac59</color>
        <width>4</width>
      </LineStyle>
      <PolyStyle>
        <color>99ffac59</color>
      </PolyStyle>
    </Style>
    <Placemark>
      <name>Absolute Extruded</name>
      <description>Transparent green wall with yellow outlines</description>
      <styleUrl>#yellowLineGreenPoly</styleUrl>
      <LineString>
        <extrude>1</extrude>
        <tessellate>1</tessellate>
        <altitudeMode>clampToGround</altitudeMode>
        <coordinates>
END

#for my $node (@{$longest_path->{path}}) {
for my $node (sort {($self->earth->bearing(@{$start_ll}, $a->{lat}, $a->{lon})) <=> ($self->earth->bearing(@{$start_ll}, $b->{lat}, $b->{lon}))} @$terminals) {
  printf $kml_out "%f,%f,0\n", $node->{lon}, $node->{lat};
}

    print $kml_out <<"END";
        </coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>
END

}

