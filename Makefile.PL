use warnings;
use strict;

use 5.006;

use inc::Module::Install '1.01';

version  '1.0';

requires 'strictures';
requires 'Geo::Ellipsoid';
requires 'LWP::Simple';
requires 'Geo::Parse::OSM::Multipass';
requires 'Data::Dump::Streamer';

author 'James Mastros <james@mastros.biz>';
license 'perl';


WriteAll;
