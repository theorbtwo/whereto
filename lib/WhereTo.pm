package WhereTo;

use strictures 1;
use autodie;
use 5.10.0;
use Geo::Ellipsoid;
use LWP::Simple 'get';
use Geo::Parse::OSM::Multipass;
use Getopt::Long;
use Data::Dump::Streamer 'Dump', 'Dumper';
use Moose;
use JSON;
# use Imager;

use WhereTo::Schema;

has schema => (is => 'ro', isa => 'DBIx::Class::Schema', lazy_build => 1);

sub _build_schema {
    return WhereTo::Schema->connect('dbi:SQLite:/mnt/shared/projects/geo/osm/whereto/whereto.db');
}

sub nodes {
    my ($self) = @_;
    return $self->schema->resultset('Node')->all();
}

## TODO:
# Add attributes for: nodes, earth, terminals, seen ?
# Refactoring: Methods return results instead of stuffing into $self, add methods to get various parts of data that can be abstracted to data storage, 
# Extract method for prettifying directions


=head2 get_region

=over

=item Arguments: \($latitude, $longitude), $radius

=item Returns: $osm_xml

=back

Pass in a starting point (arrayref of latitude and longitude of the
center), and get back the OSM XML representing the area $radius miles
around that point. (The square circumscribing the circle, since the
OSM API call takes a bounding box.)

=cut

sub get_region {
  my ($self, $center, $radius) = @_;

  my $earth = $self->earth;
  (my $north, undef) = $earth->at(@$center, $radius, 0);
  (undef, my $east)  = $earth->at(@$center, $radius, 90);
  (my $south, undef) = $earth->at(@$center, $radius, 180);
  (undef, my $west)  = $earth->at(@$center, $radius, 180);

  $self->debugf ("North:  %f\n", $north);
  $self->debugf ("Center: %f\n", $center->[0]);
  $self->debugf ("South:  %f\n", $south);

  $self->debugf ("West:   %f\n", $west);
  $self->debugf ("Center: %f\n", $center->[1]);
  $self->debugf ("East:   %f\n", $east);

  ## Wot no CPAN module for this?
  my $url = 'http://api.openstreetmap.org/api/0.6/map?bbox='.join(',', $west, $south, $east, $north);
  $self->debug( "Fetching $url\n" );

  my $xml = get($url);
  #print $xml, "\n\n";

  #my $xml = 'map?bbox=-1.77032811520983,51.5665801990025,-1.71286446285378,51.6023787132927';

  return $xml;
}

=head2 parse_osm_xml

=over

=item Arguments: $osm_xml

=item Returns: $self (and runs the osm_handler callback for each data bit)

=back

Pass in the OSM XML for an area of map, this method uses
L<Geo::Parse::OSM::Multipass> to iterate over the data and call the
L</osm_handler> callback.

=cut

sub parse_osm_xml {
  my ($self, $xml) = @_;

  my $parser = Geo::Parse::OSM::Multipass->new(\$xml,
                                               pass2 => sub {$self->osm_handler(@_)},                                             );

  $parser->parse(sub {});

  return $self;
}

=head2 osm_handler

=over

=item Arguments: \%bit, $parser

=item Returns: Nothing (stores the nodes and related ways in $self->{nodes})

=back

Called by the L</parse_osm_xml> method as a callback to
L<Geo::Parse::OSM::Multipass>'s parser. Stores all the nodes and their
attached ways in $self->{nodes}.

=cut

sub osm_handler {
  my ($self, $bit, $parser) = @_;

  $bit = {%$bit};

  #Dump $bit;

  given ($bit->{type}) {
    when ('bound') {
      push @{$self->{known}}, $bit;
    };

    when ('node') {
#      $self->{nodes}{$bit->{id}} = $bit;
        $self->add_node($bit);
    };

    when ('way') {
      $self->add_way($bit);
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

sub add_node {
    my ($self, $bit) = @_;

    my $tags = $bit->{tag} ? JSON::encode_json($bit->{tag}) : undef;
    $self->schema->resultset('Node')->find_or_create({
        id => $bit->{id},
        latitude => $bit->{lat},
        longitude => $bit->{lon},
        uid => $bit->{uid},
        tags => $tags,
    }, { key => 'primary'});

#    $self->{nodes}{$bit->{id}} = $bit;
}

sub add_way {
    my ($self, $bit) = @_;

    my $tags = $bit->{tag} ? JSON::encode_json($bit->{tag}) : undef;
    my $way = $self->schema->resultset('Way')->find_or_create({
        id => $bit->{id},
        uid => $bit->{uid},
        tags => $tags,
    });

    foreach my $node (@{$bit->{chain}}) {
#        $self->debug("New chain: $node, ". $bit->{id}. "\n");
        my $chain = $way->find_or_create_related('chains', { node_id => $node });
    }

    # my @nodes = @{$bit->{chain}};
    
    # for my $i (0..@nodes-1) {
    #     my $prev_id = $i>0 ? $nodes[$i-1] : undef;
    #     my $this_id = $nodes[$i];
    #     my $next_id = $i<@nodes-1 ? $nodes[$i+1] : undef;
        
    #     push @{$self->{nodes}{$this_id}{links}}, [$bit, $prev_id] if $prev_id;
    #     push @{$self->{nodes}{$this_id}{links}}, [$bit, $next_id] if $next_id;
    # }
}

=head2 filter_node

=item Arguments: $node

=item Returns: True value if this node is on a linked way, False if not

=back

Discovers whether the given node is part of a way that is also
walkable (filtered by L</filter_link>.

=cut

sub filter_node {
  my ($self, $node) = @_;
  
  #print "Filtering node: $node\n";
  #Dump $node;

  # No links -- it's a PoI, not a part of a way.
  return 0 if !$node->chains->count;

  # If any of the potential links are something that we can walk on, keep the node.
  for my $link (@{$node->links}) {
    return 1 if $self->filter_link($link);
  }

  return 0;
}

=head2 filter_link

=over

=item Arguments: $link

=item Returns: True if the link is walkable, False otherwise

=back

Discover whether a given link (part of a way) is actually walkable,
that is not part of a boundary, river etc. See L<http://wiki.openstreetmap.org/wiki/Map_Features>.

=cut

sub filter_link {
  my ($self, $link) = @_;

  return 0 if( !$link->[0]->tags );

  return 1 if (($link->[0]->tags->{foot}||'x') ~~ [qw<yes>]);

  return 0 if $link->[0]->tags->{proposed};

  #print "Filtering link:\n";
  #print "From ", join(" // ", map {$_//"undef"} caller(0)), "\n";
  #Dump $link;
  # Big roads that you shouldn't walk on.
  return 0 if ($link->[0]->tags->{highway}||'x') ~~ ['trunk', 'trunk_link'];
  
  # Things that you can't walk through.
  return 0 if ($link->[0]->tags->{barrier}||'x') ~~ ['hedge', 'wall'];
  if ($link->[0]->tags->{barrier}) {
    $self->debug("Barrier: ", $link->[0]->tags->{barrier}, "\n" );
  }
  
  return 0 if (($link->[0]->tags->{railway}||'x') ~~ [qw<rail platform>]);

  # I'd like to exclude all areas, but there's not really a good mechanical way to do that presently.
  # All valid areas will have a $link->[0]{outer}, but that's also true of any circular feature -- such as a roundabout.
  return 0 if $link->[0]->tags->{amenity};
  return 0 if $link->[0]->tags->{landuse};
  return 0 if (($link->[0]->tags->{leisure}||'x') ~~ [qw<park playground pitch>]);
  return 0 if $link->[0]->tags->{building};
  return 0 if $link->[0]->tags->{boundary};

  return 1;
}

=head2

=over

=item Arguments: \($latitude, $longitude)

=item Returns: Actual closest OSM node that is also on a Way.

=back

Given a point defined by a lat/long, find the closest OSM node that is
part of a (walkable) way.

=cut

sub find_nearest_node {
  my ($self, $ll) = @_;

  my $earth = $self->earth;

  my ($best_dist, $best_node) = (9e999, undef);
  for my $node ($self->nodes) {
    next if !$self->filter_node($node);

    my $dist = $earth->range(@$ll, $node->latitude, $node->longitude);
    if ($best_dist > $dist) {
      $best_dist = $dist;
      $best_node = $node;
    }
  }

  $self->debug("find_nearest_node: best node was $best_dist miles away\n" );
  return $best_node;
}

=head2

=over

=item Arguments: None

=item Returns: Geo::Ellipsoid object represnting the earth

=back

Main object for calculating distances and new coordinates.

=cut


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

=head2

=over

=item Arguments: $filehandle

=item Returns: Nothing

=back

Writes a tab separated set of data representing all the nodes that can
be reached from the start point, and directions to reach them, to the
given filehandle.

This is in a format that the OpenLayers Text Format will read.

=cut


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
        my $bearing = $earth->bearing($prev_node->latitude,
                                      $prev_node->longitude,
                                      $pathelem->{node}->latitude,
                                      $pathelem->{node}->longitude);
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
        my $highway = $pathelem->{way}->tags->{highway} // 'undef';

        if (exists $pathelem->{way}->tags->{name}) {
          $waydesc = $pathelem->{way}->tags->{name};
        } elsif ($pathelem->{way}->tags->{ref}) {
          $waydesc = 'the '.$pathelem->{way}->tags->{ref};
        } elsif (($pathelem->{way}->tags->{junction}||'x') eq 'roundabout') {
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
        } elsif (($pathelem->{way}->tags->{amenity} || 'x') eq 'parking') {
          $waydesc = 'a parking lot';
        } elsif (not keys %{$pathelem->{way}->tags}) {
          $waydesc = '???';
        } elsif (($pathelem->{way}->tags->{railway} || "x") eq 'disused') {
          $waydesc = 'a disused rail track';
        } elsif (($pathelem->{way}->tags->{waterway}||'x') eq 'river') {
          $waydesc = 'a river';
        } elsif (($pathelem->{way}->tags->{waterway}||'x') eq 'stream') {
          $waydesc = 'a stream';
        } elsif ($highway eq 'footway') {
          $waydesc = 'a footpath';
        } else {
          Dump $pathelem;
          die "Don't know how to describe this way";
        }

        if ($pathelem->{way}->tags->{bridge}) {
          $waydesc .= " bridge";
        }

        $desc .= "go $bearing_word on $waydesc<br/>";
      }

      $prev_node = $pathelem->{node};
      $prev_way = $pathelem->{way};
    }
    
    print $fh join("\t", $end_node->latitude, $end_node->longitude, $path->{pathlen}, $desc), "\n";
  }
}

=head2 write_kml

=over

=item Arguemnts: \($startlat, $startlon), $terminal_nodes, $filename

=item Returns: Nothing, writes to the filename

=back

Writes out KML data representing the nodes reached from the start point.

=cut

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

=head2 calculate_paths

=over

=item Arguments: \($startlat, $startlon), $distmiles, $filename

=over Returns: Nothin, stuffs results into $self->{terminals}, $self->{seen}

=back

Given a starting point (in lat/long), calculates all the paths to
nodes that are at most $distmiles away from the starting point. Stores
the results in $self->{terminals} and $self->{seen}.

=cut


sub calculate_paths {
    my ($self, $start_ll, $target_len, $filename) = @_;
#    my $start_ll = [51.584483, -1.741585];
#    my $target_len = 1.75;
    my $osm_xml = $self->get_region($start_ll, $target_len);
    $self->parse_osm_xml($osm_xml);

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

        if (exists $seen{$here->id}) {
            if ($seen{$here->id}{pathlen} > $this_path->{pathlen}) {
                $self->debug( "Hmm, found a shorter path later?  Shouldn't happen.\n");
            }
            next;
        }

        $seen{$here->id} = $this_path;

        if ($this_path->{pathlen} > $longest_path->{pathlen}) {
            $longest_path = $this_path;
        }

        for my $link (@{$here->links}) {
            next unless $self->filter_link($link);

#            my $new_node = $self->{nodes}{$link->[1]};
            my $new_node = $link->[1];

            my $new_path_elem = {
                                 node => $new_node,
                                 way  => $link->[0]
                                };
            my $new_len = $earth->range($here->latitude,
                                        $here->longitude,
                                        $new_node->latitude,
                                        $new_node->longitude);
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

        if (not @{$here->links}) {
            # Hmm.  This is the presumable cause of "gaps" in the outer rim.  OTOH, putting in all of these will make it no longer a rim so much as a bunch of dead ends.
            # I see no clear way of fixing this outside of completely revamping the UI... which I planned to do anyway.
        }
    }

#print "Longest path found: \n";
#print Dumper $longest_path;

    $self->{terminals} = \@terminals;
    $self->{seen} = \%seen;
}

sub debugf {
    my ($self, @content) = @_;

    printf STDERR @content;
}

sub debug {
    my ($self, @content) = @_;

    print STDERR @content;
}

'Found it!';

=head1 GLOSSARY

=head2 node

=head2 link
