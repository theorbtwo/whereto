package WhereTo::Schema::Result::Chain;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->load_components(qw/Ordered/);
__PACKAGE__->table('chains');
__PACKAGE__->add_columns(
    ## Supplied by OSM
    way_id => {
        data_type => 'integer',
    },
    node_id => {
        data_type => 'integer',
    },
    position => {
        data_type => 'integer',
    }
    );

__PACKAGE__->set_primary_key(qw/way_id node_id/);
__PACKAGE__->position_column('position');
__PACKAGE__->grouping_column('way_id');
__PACKAGE__->belongs_to('way', 'WhereTo::Schema::Result::Way', 'way_id');
__PACKAGE__->belongs_to('node', 'WhereTo::Schema::Result::Node', 'node_id');

'done coding';
