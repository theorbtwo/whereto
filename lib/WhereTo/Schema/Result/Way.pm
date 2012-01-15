package WhereTo::Schema::Result::Way;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->load_components(qw/InflateColumn::Serializer TimeStamp/);
__PACKAGE__->table('ways');
__PACKAGE__->add_columns(
    ## Supplied by OSM
    id => {
        data_type => 'integer',
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
__PACKAGE__->has_many('chains', 'WhereTo::Schema::Result::Chain', 'way_id');

'done coding';
