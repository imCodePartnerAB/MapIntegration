package Koha::Plugin::MapIntegration;

use C4::Languages;
use Modern::Perl;
use Koha::AuthorisedValues;
use Koha::Biblios;
use Koha::Items;
use Koha::Item;

use JSON;

use C4::Biblio qw(
    GetBiblioData);

use base qw(Koha::Plugins::Base);

our $VERSION = "1.0.6";

our $metadata = {
    name            => 'Map Integration',
    author          => 'imCode.com.',
    date_authored   => '2023-12-01',
    date_updated    => "2026-09-02",
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
            path_host        => $self->retrieve_data('path_host'),
            include_subtitle => $self->retrieve_data('include_subtitle'),
        );

        return $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                path_host        => $cgi->param('host'),
                include_subtitle => $cgi->param('include_subtitle') ? 1 : 0,
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
    my $dat_json = to_json($dat, { utf8 => 0, pretty => 0 }); 

    #inspired by opac-detail.pl
    my $shelflocations =
    { map { $_->{authorised_value} => $_->{opac_description} } Koha::AuthorisedValues->get_descriptions_by_koha_field( { frameworkcode => $dat->{frameworkcode}, kohafield => 'items.location' } ) };
    my $collections =
    { map { $_->{authorised_value} => $_->{opac_description} } Koha::AuthorisedValues->get_descriptions_by_koha_field( { frameworkcode => $dat->{frameworkcode}, kohafield => 'items.ccode' } ) };

    my $js = "<script> const item_paths = [];";
    my $host = $self->retrieve_data('path_host');
    my $include_subtitle = $self->retrieve_data('include_subtitle') ? 'true' : 'false';
    $js .= "var host = \"" . $host . "\";";
    $js .= "var prompt = \"" . $prompt . "\";";
    $js .= "var include_subtitle = " . $include_subtitle . ";";
    $js .= "var collections = {};";
    $js .= "var locations = {};";
    $js .= "var dat_json = " . $dat_json . ";";
    $js .= "var call_number = 'test' ;";

    while (my $item = $items->next) {

        my $marc_record = $item->biblio->metadata->record;
        my $call_number = "";
        if ($marc_record) {
            my $marc_as_string = $marc_record ? $marc_record->as_formatted() : "No MARC data";
            my $marc_json = to_json($marc_as_string, { utf8 => 1 });
            # $js .= "console.log('MARC:', " . $marc_json . ");";
        
            my $field_952 = $marc_record->field('952');
            if ($field_952) {
                $call_number = $field_952->subfield('o') || ""; 
            } else {
                $call_number = ""; 
            }

            $js .= "var call_number = \"" . $call_number . "\";";
        }
        
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

          var b = $.trim(t).split('(')[0];

          var shelf = b;
                    
          var location = shelvingLocation in locations ? locations[shelvingLocation] : "";
          var ccode = collectionDesc in collections ? collections[collectionDesc] : "";

          var titleText = include_subtitle && dat_json.subtitle ? dat_json.title + " " + dat_json.subtitle : dat_json.title;
          var wagnerGuidePath = host + "?department=" + ccode + "&location=" + location + "&shelf=" + shelf + "&text=" + encodeURIComponent(titleText);

          $(callNoTd).append("<a href=\"" + wagnerGuidePath + "\">" + prompt + "</a>");
          // console.log("JSON DAT: " , dat_json);
          // console.log("Call number: " , call_number);
          });

JS

    $js .= "</script>";

    return $js;
    
    }
}

1;
