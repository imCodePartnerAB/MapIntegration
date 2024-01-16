package Koha::Plugin::MapIntegration;

use C4::Languages;
use Modern::Perl;
use Koha::AuthorisedValues;
use Koha::Biblios;
use Koha::Items;
use Koha::Item;

use C4::Biblio qw(
    GetBiblioData);

use base qw(Koha::Plugins::Base);

our $VERSION = "0.1.3";

our $metadata = {
    name            => 'Map Integration',
    author          => 'imCode.com',
    date_authored   => '2023-12-01',
    date_updated    => "2024-01-15",
    minimum_version => '21.11.00.000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'This plugin integrates map links for items.',
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);
    $self->{cgi} = CGI->new();

    return $self;
}

sub configure {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save')) {

        my $template = $self->get_template( { file => 'configure.tt' } );

        ## Grab value if exist
        $template->param(
            path_host => $self->retrieve_data('path_host'),
        );

        return $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                path_host => $cgi->param('host')
            }
        );
        $self->go_home();
    }
}

sub opac_js {
    my ( $self ) = @_;
    my $cgi = $self->{'cgi'};
    my $script_name = $cgi->script_name;

    if ($script_name =~ /opac-detail\.pl/) {

    my $language = C4::Languages::getlanguage();

    my $prompt = "Locate shelf";
    if ($language eq "sv-SE") {
        $prompt = "Hitta till hyllan";
    }

    my $biblionumber = $cgi->param('biblionumber');

    my $biblio = Koha::Biblios->find($biblionumber);

    my $items = Koha::Items->search( { biblionumber => $biblionumber });

    my $dat = &GetBiblioData($biblionumber);

    #inspired by opac-detail.pl
    my $shelflocations =
    { map { $_->{authorised_value} => $_->{opac_description} } Koha::AuthorisedValues->get_descriptions_by_koha_field( { frameworkcode => $dat->{frameworkcode}, kohafield => 'items.location' } ) };
    my $collections =
    { map { $_->{authorised_value} => $_->{opac_description} } Koha::AuthorisedValues->get_descriptions_by_koha_field( { frameworkcode => $dat->{frameworkcode}, kohafield => 'items.ccode' } ) };

    my $js = "<script> const item_paths = [];";
    my $host = $self->retrieve_data('path_host');
    $js .= "var host = \"" . $host . "\";";
    $js .= "var prompt = \"" . $prompt . "\";";
    $js .= "var collections = {};";
    $js .= "var locations = {};";

      while (my $item = $items->next) {
        
            if (defined $item->ccode && $item->ccode ne "") {
            $js .= "collections[\"" . $collections->{$item->ccode} . "\"] = \"" . $item->ccode . "\";";  
            } 
            if (defined $item->location && $item->location ne "" ) {
            $js .= "locations[\"" . $shelflocations->{$item->location} . "\"] = \"" . $item->location . "\";";  
        }     
}
        
      


    $js .= <<'JS'; 

        $('#holdingst').find("tbody").find("tr").each(function(index) {

          var collectionDesc = $(this).find(".collection").text();
          var shelvingLocationspan = $(this).find(".shelving_location").find(".shelvingloc");
          var shelvingLocation = $(shelvingLocationspan).text();

          var callNoTd = $(this).find(".call_no");

          var t = $(callNoTd).text();

          var b = $.trim(t).split(' ');

          var shelf = b[0];
          
          var location = shelvingLocation in locations ? locations[shelvingLocation] : "";
          var ccode = collectionDesc in collections ? collections[collectionDesc] : "";

          var wagnerGuidePath = host + "?department=" + ccode + "&location=" + location + "&shelf=" + shelf;

          $(callNoTd).append("<a href=\"" + wagnerGuidePath + "\">" + prompt + "</a>");
          });

JS

    $js .= "</script>";

    return $js;

    }
}

1;