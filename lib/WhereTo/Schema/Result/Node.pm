package WhereTo::Schema::Result::Node;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->load_components(qw/InflateColumn::Serializer TimeStamp/);
__PACKAGE__->table('nodes');
__PACKAGE__->add_columns(
    ## Supplied by OSM
    id => {
        data_type => 'integer',
    },
    latitude => {
        data_type => 'float',
    },
    longitude => {
        data_type => 'float',
    },
    uid => {
        data_type => 'integer',
        is_nullable => 1,
    },
    tags => {
        data_type => 'varchar',
        size => 2048,
        serializer_class   => 'JSON',
        is_nullable => 1,
    },
    cached => {
        data_type => 'datetime',
        set_on_create => 1,
    },
    );

__PACKAGE__->set_primary_key(qw/id/);
__PACKAGE__->has_many('chains', 'WhereTo::Schema::Result::Chain', 'node_id');

sub links {
    my ($self) = @_;

    if ($self->{cached_links}) {
      return $self->{cached_links};
    }

    my @chains = $self->chains->search({}, {
        order_by => [{ '-asc' => 'position' }],
        prefetch => ['way'],
                                       });
#    my @chains = $self->chains->as_subselect->search_related('way')->search_related('chains', {}, {order_by => [{ '-asc' => 'position' }]});
## ??

    my @links = ();
    for my $chain (@chains) {
        # Can probably be sped up, if made less simple, by searching WHERE position = $chain->position + 1 OR position = $chain->position - 1

        # If position is 1, we're at the beginning of the way.
        if ($chain->position > 1) {
            my $prev = $chain->way->chains->search({ position => $chain->position-1 })->single->node;
#            my $prev = 'get node on way $chain->way with position $chain->position+1';
            push @links, [$chain->way, $prev, -1];
        }
        my $next = $chain->way->chains->search({ position => $chain->position+1 })->single;
#        my $next = 'as $prev above, but $chain->position-1';
        # no next is fine, we are at end of way.
        if ($next) {
            push @links, [$chain->way, $next->node, 1];
        }
    }


    # for my $i (0..@chains-1) {
    #     my $prev = $i>0 ? $chains[$i-1]->node : undef;
    #     my $this = $chains[$i]->node;
    #     my $next = $i<@chains-1 ? $chains[$i+1]->node : undef;
        
    #     push @links, [$chains[$i]->way, $prev] if $prev;
    #     push @links, [$chains[$i]->way, $next] if $next;
    # }

    $self->{cached_links} = \@links;

    return \@links;
}

'done coding';
