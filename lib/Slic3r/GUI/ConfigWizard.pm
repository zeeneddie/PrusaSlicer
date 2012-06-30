package Slic3r::GUI::ConfigWizard;
use strict;
use warnings;
use utf8;

use Wx qw(:bitmap);
use base 'Wx::Wizard';

sub new {
    my $class = shift;
    my ($parent) = @_;
    # TODO: Add instructional bitmaps
    my $self = $class->SUPER::new($parent, -1, 'Configuration Wizard',
                                  Wx::Bitmap->new("$Slic3r::var/Slic3r_128px.png", wxBITMAP_TYPE_PNG));

    # Start from sane defaults
    $self->{old} = Slic3r::Config->current;
    Slic3r::Config->load_hash($Slic3r::Defaults, undef, 1);

    $self->add_page(Slic3r::GUI::ConfigWizard::Page::Welcome->new($self));
    $self->add_page(Slic3r::GUI::ConfigWizard::Page::Firmware->new($self));
    $self->add_page(Slic3r::GUI::ConfigWizard::Page::Bed->new($self));
    $self->add_page(Slic3r::GUI::ConfigWizard::Page::Nozzle->new($self));
    $self->add_page(Slic3r::GUI::ConfigWizard::Page::Filament->new($self));
    $self->add_page(Slic3r::GUI::ConfigWizard::Page::Temperature->new($self));
    $self->add_page(Slic3r::GUI::ConfigWizard::Page::BedTemperature->new($self));
    $self->add_page(Slic3r::GUI::ConfigWizard::Page::Finished->new($self));

    return $self;
}

sub add_page {
    my $self = shift;
    my ($page) = @_;

    my $n = push @{$self->{pages}}, $page;
    # add first page to the page area sizer
    $self->GetPageAreaSizer->Add($page) if $n == 1;
    # link pages
    $self->{pages}[$n-2]->set_next_page($page) if $n >= 2;
    $page->set_previous_page($self->{pages}[$n-2]) if $n >= 2;
}

sub run {
    my $self = shift;

    my $modified;
    if (Wx::Wizard::RunWizard($self, $self->{pages}[0])) {
        $_->apply for @{$self->{pages}};
        $modified = 1;
    } else {
        Slic3r::Config->load_hash($self->{old}, undef, 1);
        $modified = 0;
    }

    $self->Destroy;

    return $modified;
}

package Slic3r::GUI::ConfigWizard::Option;
use Wx qw(:combobox :misc :sizer :textctrl);
use Wx::Event qw(EVT_SPINCTRL EVT_TEXT EVT_CHECKBOX EVT_COMBOBOX);
use base 'Wx::StaticBoxSizer';

sub new {
    my $class = shift;
    my ($parent, %params) = @_;
    my $box = Wx::StaticBox->new($parent, -1, '');
    my $self = $class->SUPER::new($box, wxHORIZONTAL);

    my $label_width = 200;

    my $opt_key = $params{option};
    my $opt = $Slic3r::Config::Options->{$opt_key};

    my $callback = $params{callback} || sub {};

    # label
    my $label = Wx::StaticText->new($parent, -1, "$opt->{label}:", wxDefaultPosition, [$label_width, -1]);
    $label->Wrap($label_width);
    $self->Add($label, 1, wxEXPAND);

    # input field(s) and unit
    my $field;
    if ($opt->{type} =~ /^(i|f|s|s@)$/) {
        my $style = $opt->{multiline} ? wxTE_MULTILINE : 0;
        my $size = Wx::Size->new($opt->{width} || -1, $opt->{height} || -1);

        my ($get, $set) = $opt->{type} eq 's@' ? qw(serialize deserialize) : qw(get_raw set);

        if ($opt->{type} eq 'i') {
            my $value = Slic3r::Config->$get($opt_key);
            $field = Wx::SpinCtrl->new($parent, -1, $value, wxDefaultPosition, $size, $style, $opt->{min} || 0, $opt->{max} || 100, $value);
            EVT_SPINCTRL($parent, $field, sub { $callback->($opt_key, $field->GetValue) });
        } else {
            $field = Wx::TextCtrl->new($parent, -1, Slic3r::Config->$get($opt_key), wxDefaultPosition, $size, $style);
            EVT_TEXT($parent, $field, sub { $callback->($opt_key, $field->GetValue) });
        }
    } elsif ($opt->{type} eq 'bool') {
        $field = Wx::CheckBox->new($parent, -1, '');
        $field->SetValue(Slic3r::Config->get_raw($opt_key));
        EVT_CHECKBOX($parent, $field, sub { $callback->($opt_key, $field->GetValue) });
    } elsif ($opt->{type} eq 'point') {
        $field = Wx::BoxSizer->new(wxHORIZONTAL);
        my $field_size = Wx::Size->new(40, -1);
        my $value = Slic3r::Config->get_raw($opt_key);
        my @items = (
            Wx::StaticText->new($parent, -1, 'x:'),
            my $x_field = Wx::TextCtrl->new($parent, -1, $value->[0], wxDefaultPosition, $field_size),
            Wx::StaticText->new($parent, -1, '  y:'),
            my $y_field = Wx::TextCtrl->new($parent, -1, $value->[1], wxDefaultPosition, $field_size),
        );
        $field->Add($_) for @items;
        EVT_TEXT($parent, $x_field, sub { $callback->($opt_key, [$x_field->GetValue, $y_field->GetValue]) });
        EVT_TEXT($parent, $y_field, sub { $callback->($opt_key, [$x_field->GetValue, $y_field->GetValue]) });
    } elsif ($opt->{type} eq 'select') {
        $field = Wx::ComboBox->new($parent, -1, '', wxDefaultPosition, wxDefaultSize, $opt->{labels} || $opt->{values}, wxCB_READONLY);
        my $value = Slic3r::Config->get_raw($opt_key);
        $field->SetSelection(grep $opt->{values}[$_] eq $value, 0..$#{$opt->{values}});
        EVT_COMBOBOX($parent, $field, sub { $callback->($opt_key, $opt->{values}[$field->GetSelection]) });
    } else {
        die 'Unsupported option type: ' . $opt->{type};
    }
    if ($opt->{sidetext}) {
        my $sizer = Wx::BoxSizer->new(wxHORIZONTAL);
        $sizer->Add($field);
        my $sidetext = Wx::StaticText->new($parent, -1, $opt->{sidetext}, wxDefaultPosition, [-1, -1]);
        $sizer->Add($sidetext, 0, wxLEFT | wxALIGN_CENTER_VERTICAL, 4);
        $self->Add($sizer);
    } else {
        $self->Add($field, 0, $opt->{full_width} ? wxEXPAND : 0);
    }

    return $self;
}

package Slic3r::GUI::ConfigWizard::Page;
use Wx qw(:font :misc :sizer :staticline :systemsettings);
use base 'Wx::WizardPage';

sub new {
    my $class = shift;
    my ($parent, $title) = @_;
    my $self = $class->SUPER::new($parent);

    $self->{width} = 400;
    $self->{vsizer} = Wx::BoxSizer->new(wxVERTICAL);
    $self->SetSizer($self->{vsizer});

    # title
    my $text = Wx::StaticText->new($self, -1, $title, wxDefaultPosition, wxDefaultSize, wxALIGN_LEFT);
    my $bold_font = Wx::SystemSettings::GetFont(wxSYS_DEFAULT_GUI_FONT);
    $bold_font->SetWeight(wxFONTWEIGHT_BOLD);
    $bold_font->SetPointSize(14);
    $text->SetFont($bold_font);
    $self->{vsizer}->Add($text, 0, wxALIGN_LEFT | wxALL, 10);
    my $line = Wx::StaticLine->new($self, -1, wxDefaultPosition, wxDefaultSize, wxLI_HORIZONTAL, '');
    $self->{vsizer}->Add($line, 0, wxEXPAND| wxALL, 10);

    return $self;
}

sub append_text {
    my $self = shift;
    my ($text) = @_;

    my $para = Wx::StaticText->new($self, -1, $text, wxDefaultPosition, wxDefaultSize, wxALIGN_LEFT);
    $para->Wrap($self->{width});
    $self->{vsizer}->Add($para, 0, wxALIGN_LEFT | wxALL, 10);
}

sub append_option {
    my $self = shift;
    my ($opt_key) = @_;

    my $option = Slic3r::GUI::ConfigWizard::Option->new($self, option => $opt_key,
                                                        callback => sub {
                                                            my ($opt_key, $value) = @_;
                                                            $self->{options}->{$opt_key} = $value;
                                                        });
    $self->{vsizer}->Add($option, 0, wxEXPAND | wxALL, 10);
}

sub apply {
    my $self = shift;
    Slic3r::Config->set($_, $self->{options}->{$_}) foreach (keys %{$self->{options}});
}

sub set_previous_page {
    my $self = shift;
    my ($previous_page) = @_;
    $self->{previous_page} = $previous_page;
}

sub GetPrev {
    my $self = shift;
    return $self->{previous_page};
}

sub set_next_page {
    my $self = shift;
    my ($next_page) = @_;
    $self->{next_page} = $next_page;
}

sub GetNext {
    my $self = shift;
    return $self->{next_page};
}

package Slic3r::GUI::ConfigWizard::Page::Welcome;
use base 'Slic3r::GUI::ConfigWizard::Page';

sub new {
    my $class = shift;
    my ($parent) = @_;
    my $self = $class->SUPER::new($parent, 'Welcome to the Slic3r Configuration Wizard');

    $self->append_text('Hello, welcome to Slic3r! This wizard helps you with the initial configuration; just a few settings and you will be ready to print.');
    $self->append_text('To import an existing configuration instead, cancel this wizard and use the Open Config menu item found in the File menu.');
    $self->append_text('To continue, click Next.');

    return $self;
}

package Slic3r::GUI::ConfigWizard::Page::Firmware;
use base 'Slic3r::GUI::ConfigWizard::Page';

sub new {
    my $class = shift;
    my ($parent) = @_;
    my $self = $class->SUPER::new($parent, 'Firmware Type');

    $self->append_text('Choose the type of firmware used by your printer, then click Next.');
    $self->append_option('gcode_flavor');

    return $self;
}

package Slic3r::GUI::ConfigWizard::Page::Bed;
use base 'Slic3r::GUI::ConfigWizard::Page';

sub new {
    my $class = shift;
    my ($parent) = @_;
    my $self = $class->SUPER::new($parent, 'Bed Size');

    $self->append_text('Enter the size of your printers bed, then click Next.');
    $self->append_option('bed_size');

    return $self;
}

sub apply {
    my $self = shift;
    $self->SUPER::apply;

    # set print_center to centre of bed_size
    my $bed_size = Slic3r::Config->get_raw('bed_size');
    Slic3r::Config->set('print_center', [$bed_size->[0]/2, $bed_size->[1]/2]);
}

package Slic3r::GUI::ConfigWizard::Page::Nozzle;
use base 'Slic3r::GUI::ConfigWizard::Page';

sub new {
    my $class = shift;
    my ($parent) = @_;
    my $self = $class->SUPER::new($parent, 'Nozzle Diameter');

    $self->append_text('Enter the diameter of your printers hot end nozzle, then click Next.');
    $self->append_option('nozzle_diameter');

    return $self;
}

sub apply {
    my $self = shift;
    $self->SUPER::apply;

    # set first_layer_height + layer_height based on nozzle_diameter
    my $nozzle = Slic3r::Config->get_raw('nozzle_diameter');
    Slic3r::Config->set('first_layer_height', $nozzle);
    Slic3r::Config->set('layer_height', $nozzle - 0.1);
}

package Slic3r::GUI::ConfigWizard::Page::Filament;
use base 'Slic3r::GUI::ConfigWizard::Page';

sub new {
    my $class = shift;
    my ($parent) = @_;
    my $self = $class->SUPER::new($parent, 'Filament Diameter');

    $self->append_text('Enter the diameter of your filament, then click Next.');
    $self->append_text('Good precision is required, so use a caliper and do multiple measurements along the filament, then compute the average.');
    $self->append_option('filament_diameter');

    return $self;
}

package Slic3r::GUI::ConfigWizard::Page::Temperature;
use base 'Slic3r::GUI::ConfigWizard::Page';

sub new {
    my $class = shift;
    my ($parent) = @_;
    my $self = $class->SUPER::new($parent, 'Extrusion Temperature');

    $self->append_text('Enter the temperature needed for extruding your filament, then click Next.');
    $self->append_text('A rule of thumb is 160 to 230 °C for PLA and 215 to 250 °C for ABS.');
    $self->append_option('temperature');

    return $self;
}

sub apply {
    my $self = shift;
    $self->SUPER::apply;

    # set first_layer_temperature to temperature + 5
    my $temperature = Slic3r::Config->get_raw('temperature');
    Slic3r::Config->set('first_layer_temperature', $temperature + 5);
}

package Slic3r::GUI::ConfigWizard::Page::BedTemperature;
use base 'Slic3r::GUI::ConfigWizard::Page';

sub new {
    my $class = shift;
    my ($parent) = @_;
    my $self = $class->SUPER::new($parent, 'Bed Temperature');

    $self->append_text('Enter the bed temperature needed for getting your filament to stick to your heated bed, then click Next.');
    $self->append_text('A rule of thumb is 60 °C for PLA and 110 °C for ABS.');
    $self->append_option('bed_temperature');

    return $self;
}

sub apply {
    my $self = shift;
    $self->SUPER::apply;

    # set first_layer_bed_temperature to temperature + 5
    my $temperature = Slic3r::Config->get_raw('bed_temperature');
    Slic3r::Config->set('first_layer_bed_temperature', $temperature + 5);
}

package Slic3r::GUI::ConfigWizard::Page::Finished;
use base 'Slic3r::GUI::ConfigWizard::Page';

sub new {
    my $class = shift;
    my ($parent) = @_;
    my $self = $class->SUPER::new($parent, 'Congratulations!');

    $self->append_text('You have successfully completed the Slic3r Configuration Wizard. ' .
                       'Slic3r is now configured for your printer and filament.');
    $self->append_text('To close this wizard and apply the newly created configuration, click Finish.');

    return $self;
}

1;
