#!/usr/bin/perl -w

package CGI::Path;

use strict;
use vars qw($VERSION);

$VERSION = "1.01";

use CGI;

sub new {
  my $type  = shift;
  my %DEFAULT_ARGS = (
    form_delete_pre_track => [],
    htm_extension         => 'htm',
    val_extension         => 'val',
    keep_no_form_session  => 0,
    my_form               => {},
    my_path               => {},
    not_a_real_key        => [qw(_begin_time _printed_pages _session_id _validated)],
    path_hash             => {
#      simple example
#      initial_step       => 'page0',
#      page0              => 'page1',
#      page1              => 'page2',
#      page2              => 'page3',
#      page3              => 'page4',
#      page4              => 'page5',
    },
    perl5lib              => $ENV{PERL5LIB} || '',
    session_only          => ['_validated'],
    session_wins          => [],
    use_session           => 1,
    validated_fresh       => {},
    WASA                  => [],
  );
  my $self = bless \%DEFAULT_ARGS, $type;

  $self->{my_module} ||= ref $self;
  $self->merge_in_args(@_);

  if($self->{use_session}) {
    $self->session;
  }

  ### don't always want to do all the extra stuff
  unless($self->{no_new_helper}) {
    $self->new_helper;
  }

  return $self;
}

sub session_dir {
  return '/tmp/path/session';
}

sub session_lock_dir {
  return '/tmp/path/session/lock';
}

sub cookies {
  my $self = shift;
  unless($self->{cookies}) {
    $self->{cookies} = {};
    my $query = CGI->new;
    foreach my $key ($query->cookie()) {
      $self->{cookies}{$key} = $query->cookie($key);
    }
  }
  return $self->{cookies};
}

sub DESTROY {
  my $self = shift;
}

sub session {
  my $self = shift;
  my $opt = shift;
  unless($self->{session}) {
    require Apache::Session::File;
    $self->{session} = {};
    tie %{$self->{session}}, 'Apache::Session::File', $self->sid, {
      Directory     => $self->session_dir,
      LockDirectory => $self->session_lock_dir,
    };
    $self->set_sid($self->{session}{_session_id});
  }
  if($opt) {
    my $opt_ref = ref $opt;
    if($opt_ref) {
      if($opt_ref eq 'HASH') {
        foreach(keys %{$opt}) {
          $self->{session}{$_} = $opt->{$_};
        }
      }
    } else {
      die "I got not a ref on session opt";
    }
  }
  return $self->{session};
}

sub sid_cookie_name {
  my $self = shift;
  return $self->my_content . "_sid";
}

sub set_cookie {
  my $self = shift;
  my ($cookie_name, $cookie_value) = @_;
  my $new_cookie = CGI::cookie
    (-name  => $cookie_name,
     -value => $cookie_value,
     );
  if (exists $ENV{CONTENT_TYPED}) {
    print qq{<meta http-equiv="Set-Cookie" content="$new_cookie">\n};
  } else {
    print "Set-Cookie: $new_cookie\n";
  }
  return;
}

sub set_sid {
  my $self = shift;
  my $sid = shift;
  $self->set_cookie($self->sid_cookie_name, $sid);
}

sub sid {
  my $self = shift;
  return $self->cookies->{$self->sid_cookie_name} || '';
}

sub merge_in_args {
  my $self = shift;
  my %PASSED_ARGS = (ref $_[0] eq 'HASH') ? %{$_[0]} : @_;
  foreach my $passed_arg (keys %PASSED_ARGS) {
    if(ref $PASSED_ARGS{$passed_arg} && ref $PASSED_ARGS{$passed_arg} eq 'HASH') {
      foreach my $key (keys %{$PASSED_ARGS{$passed_arg}}) {
        $self->{$passed_arg}{$key} = $PASSED_ARGS{$passed_arg}{$key};
      }
    } else {
      $self->{$passed_arg} = $PASSED_ARGS{$passed_arg}
    }
  }
}

### morph methods

sub morph_path {
  my $self = shift;
  my $my_module = shift || $self->my_module;

  # morph to my_module
  if($my_module) {
    $self->morph($my_module);
  }

}

sub morph_step {
  my $self = shift;

  my $step = shift;
  # going to morph based on my_module

  my $full_step = $self->my_module . "::$step";

  # morph to something like CGI::Path::Skel::page_one
  # the 1 turns on the -e check
  $self->morph($full_step, 1);
  
}

sub morph {
  my $self = shift;

  my $starting_ref = ref $self;

  my $package = shift;
  my $do_dash_e_check = shift;

  my $tmp_package = $package;
  $tmp_package =~ s@::@/@g;

  my $path = "$tmp_package.pm";

  my $exists = 1;

  # if they don't want to force the require, I will check -e before morphing
  if($do_dash_e_check) {
    my $full_path = "$self->{perl5lib}/$path";
    $exists = -e $full_path;
  }

  if($exists) {
    ### polymorph
    eval {
      require $path;
    };
    if( $@ ){
      $self->{errstr} = "bad stuff on require of $tmp_package.pm: $@";
      die $@;
    }
    bless $self, $package;
  }

  my $ending_ref = ref $self;

  if($self->can('add_WASA')) {
    $self->add_WASA($starting_ref);
    $self->add_WASA($ending_ref);
  }
  return $self;
}

sub add_WASA {
  my $self = shift;
  my $ref = shift;
  push @{$self->{WASA}}, $ref unless(grep { $_ eq $ref } @{$self->{WASA}});
}


sub my_module {
  my $self = shift;
  return $self->{my_module};
}

sub base_include_path {
  my $self = shift;
  die "please write your own base_include_path method";
}

sub include_path {
  my $self = shift;
  return [$self->base_include_path . "/default"];
}

sub my_content {
  my $self = shift;
  return $self->{my_content} ||= do {
    my $my_content = lc($self->my_module);
    my $this_package = __PACKAGE__;
    $my_content =~ s/^${this_package}:://i;
    $my_content =~ s@::@/@g;
    $my_content; # return of the do
  };
}




sub new_helper {
  my $self = shift;

  if(!$self->{keep_no_form_session} && !scalar keys %{$self->this_form} && 
    scalar keys %{$self->session}) {
    #warn "User posted an empty form with a non empty session.\n";
    $self->session_wipe;
  }

  $self->generate_form;
  $self->morph_path;
  $self->get_path_array;

  unless($self->session->{_begin_time}) {
    $self->session({
      _begin_time => time,
    });
  }
  if($ENV{HTTP_REFERER} && $ENV{SCRIPT_NAME}
  && $ENV{HTTP_REFERER} !~ $ENV{SCRIPT_NAME}) {
    $self->session({
      http_referer => $ENV{HTTP_REFERER},
    });
  }
}

sub delete_session {
  my $self = shift;
  delete $self->{session};
}

sub session_wipe {
  my $self = shift;
  my $no_error = shift;
  $self->delete_cookie($self->sid_cookie_name);
  $self->delete_session;
  if(keys %{$self->this_form}) {
    die "need to get session_wipe to work generally";
  }
}

sub delete_cookie {
  my $self = shift;
  my $cookie_name = shift || die "need a cookie_name for delete_cookie";

  if($self->cookies->{$cookie_name}) {
    delete $self->cookies->{$cookie_name};
    $self->set_cookie($cookie_name, '');
  }
}

sub get_path_array {
  my $self = shift;

  my $path_hash = $self->path_hash;

  $self->{path_array} = [];
  my $next_step = $self->initial_step || die "need an initial_step";
  while($next_step) {
    die "infinite loop on $next_step" if(grep {$next_step eq $_ } @{$self->{path_array}});
    push @{$self->{path_array}}, $next_step;

    $next_step = $path_hash->{$next_step};
  }
  return $self->{path_array};
}

sub session_form {
  return {};
}

sub generate_form {
  # generate_form takes two hashes
  # $self->this_form - the results of CGI get form
  # $self->session   - the stuff from the session file
  # and merges them into
  # $self->{form} - the place to use
  my $self = shift;
  my $form = {};

  my $this_form = $self->this_form;
  # some things we want to just get from the session
  foreach(@{$self->{session_only}}) {
    delete $this_form->{$_};
    $form->{$_} = $self->session->{$_} if(exists $self->session->{$_});
  }

  # there might be some stuff we want to give session precedence to
  foreach(@{$self->{session_wins}}) {
    $form->{$_} = $self->session->{$_} if(exists $self->session->{$_});
  }

  # lay the hashes on top of each other in reverse order of precedence
  $self->{form} = {%{$self->session}, %{$this_form}, %{$form}};
  if($self->{form}{session_wipe}) {
    $self->session_wipe;
    $self->clear_value('session_wipe');
  }
}

sub this_form {
  my $self = shift;
  return $self->{this_form} ||= do {
    my $cgi = CGI->new;
    my %form = $cgi->Vars;
    \%form;
  }
}

sub form {
  my $self = shift;
  return $self->{form} || {};
}

sub navigate {
  my $self = shift;
  my $form = $self->form;
  my $path = $self->get_path_array;

  $self->get_unvalidated_keys;
  $self->handle_jump_around;

  my $previous_step = $form->{_printed_pages} && $form->{_printed_pages}[-1] ? $form->{_printed_pages}[-1] : '';

  ### foreach path, run the gamut of routines
  my $return_val = undef;
  foreach my $step (@$path){
    
    return 1 if($self->{stop_navigate});
    $self->morph_step($step);

    $self->{this_step} = {
      this_step     => $step,
      previous_step => $previous_step,
      validate_ref  => $self->get_validate_ref($step),
    };
    
    my $method_pre  = "${step}_hook_pre";
    my $method_fill = "${step}_hash_fill";
    my $method_form = "${step}_hash_form";
    my $method_err  = "${step}_hash_errors";
    my $method_step = "${step}_step";
    my $method_post = "${step}_hook_post";

  # my $method_val  = "${step}_validate";
  #     method_val gets called in $self->validate

    ### a hook beforehand
    if( $self->can($method_pre) ){
      $return_val = $self->$method_pre();
      if($return_val) {
        next;
      }
    }

    my $validated = 1;
    my $info_exists;

    if($self->info_exists($step)) {
      $info_exists = 1;
      $validated = $self->validate($step);
    } else {
      $info_exists = 0;
    }

    ### see if information is complete for this step
    if( ! $info_exists || ! $validated) {

      if($self->can($method_fill)) {
        $self->add_to_fill($self->$method_fill);
      }
      unless($self->fill && keys %{$self->fill}) {
        $self->add_to_fill($self->form);
      }
      my $hash_form = $self->can($method_form) ? $self->$method_form() : {};
      my $hash_err  = $self->can($method_err)  ? $self->$method_err()  : {};

      my $page_to_print;
      if($self->can($method_step)) {
        my $potential_page_to_print = $self->$method_step();

        # want to make this the page_to_print only if it a real page
        if($potential_page_to_print && !ref $potential_page_to_print && $potential_page_to_print !~ /^\d+$/) {
          $page_to_print = $potential_page_to_print 
        }

      }

      $page_to_print ||= $self->my_content . "/$step";

      my $val_ref = $self->{this_step}{validate_ref};
      $self->{my_form}{js_validation} = $self->generate_js_validation($val_ref);

      $self->print($page_to_print,
                   $hash_form,
                   $hash_err,
                   $form,
                   );
      return;
    }

    ### a hook after
    if( $self->can($method_post) ){
      $return_val = $self->$method_post();
      if($return_val) {
        next;
      }
    }

  }
  return if $return_val;

  return $self->print($self->my_content . "/" . $self->initial_step ,$form);
}

sub generate_js_validation {
  my $self = shift;
  my $val_ref = shift;
  require Embperl::Form::Validate;
  my $epf = new Embperl::Form::Validate($val_ref);
  return "<SCRIPT>\n" . ($epf->get_script_code) . "</SCRIPT>\n";
}

sub handle_jump_around {
  my $self = shift;

  warn "get handle_jump_around to work";
  return;
  my $path = $self->get_path_array;

  foreach my $step (reverse @{$path}) {
    if($self->fresh_form_info_exists($step)) {
      my $save_validated = delete $self->form->{_validated}{$step};

      foreach my $page_to_come (@{$self->pages_after_page($step)}) {

        if($self->page_has_displayed($page_to_come)) {
          my $cleared = 0;
          my $val_hash = $self->get_validate_ref($page_to_come);
          warn "get WipeOnBack to work";
          #foreach my $val_key (keys %{$val_hash}) {
          #  next unless($val_hash->{$val_key} && ref $val_hash->{$val_key} && ref $val_hash->{$val_key} eq 'HASH');
          #  if($val_hash->{$val_key}{WipeOnBack} && (! exists $self->this_form->{$val_key}) && exists $self->form->{$val_key}) {
          #    $self->clear_value($val_key);
          #    $cleared = 1;
          #  }
          #}

          if($cleared) {
            $save_validated .= delete $self->form->{_validated}{$page_to_come};
            ### need to make it look like these pages never got printed
            for(my $i=(scalar @{$self->form->{_printed_pages}}) - 1;$i>=0;$i--) {
              if($self->form->{_printed_pages}[$i] eq $page_to_come) {
                splice @{$self->form->{_printed_pages}}, $i, 1;
              }
            }
          }
        }
      }
      if($save_validated) {
        $self->save_value('_validated');
      }
    }
  }
}

sub pages_after_page {
  my $self = shift;
  my $step = shift;
  my $return = [];
  my $after = 0;
  foreach my $path_step (@{$self->get_path_array}) {
    push @{$return}, $path_step if($after);
    if($path_step eq $step) {
      $after = 1;
    }
  }
  return $return;
}

sub get_unvalidated_keys {
  my $self = shift;
  $self->{unvalidated_keys} = {%{$self->form}} || {};
  foreach(@{$self->{not_a_real_key}}) {
    delete $self->{unvalidated_keys}{$_};
  }
}

sub handle_unvalidated_keys {
  my $self = shift;
  warn "get handle_unvalidated_keys working again";
  return;
  my $path = $self->get_path_array;

  my $form = $self->form;

  my $validated = $form->{_validated} || {};
  my $mini_validated = {%$validated};

  foreach my $step (@$path){

    last unless(keys %{$self->{unvalidated_keys}});
    next if($mini_validated->{$step});

    my $val_hash = $self->get_validate_ref($step);

    my $to_save = {};
    foreach(keys %{$self->{unvalidated_keys}}) {
      if($self->{unvalidated_keys}{$_} && $form->{$_} && !$val_hash->{$_ . "_error"}) {
        $to_save->{$_} = $form->{$_};
      }
    }
    if(keys %$to_save) {
      $self->validate_unvalidated_keys($self->get_validate_ref($to_save));
      $self->session($to_save);
    }
  }
}

sub validate_unvalidated_keys {
  my $self = shift;
  my $validating_keys = shift;

  foreach(@{$validating_keys}) {
    delete $self->{unvalidated_keys}{$_};
  }
}

sub initial_step {
  my $self = shift;
  return $self->path_hash->{initial_step};
}

sub path_hash {
  my $self = shift;
  return $self->{path_hash} || die "need a hash ref for \$self->{path_hash}";
}

sub my_path {
  my $self = shift;
  return $self->{my_path};
}

sub my_path_step {
  my $self = shift;
  my $step = shift;
  $self->my_path->{$step} ||= {};
  return $self->my_path->{$step};
}

sub get_validate_ref {
  my $self = shift;

  my $step = shift;
  my $return;
  my $step_hash = $self->my_path_step($step);
  if($step_hash && $step_hash->{validate_ref}) {
    $return = $step_hash->{validate_ref};
  } else {
    $step_hash->{validate_ref} = $return = $self->include_validate_ref($self->my_content . "/$step");
  }
  return $return;
}

sub include_validate_ref {
  my $self = shift;

  # step is the full step like path/skel/enter_info
  my $step = shift;

  my $val_filename = $self->get_full_path($self->step_with_extension($step, $self->{val_extension}));
  return -e $val_filename ? $self->conf_read($val_filename) : [];
}

sub conf_read {
  my $self = shift;
  my $filename = shift;
  require XML::Simple; 
  my $ref = XML::Simple::XMLin($filename);
  return $ref;
}

sub get_full_path {
  my $self = shift;
  my $relative_path = shift;
  my $dirs = shift || $self->include_path;
  my $full_path = '';
  foreach my $dir (GET_VALUES($dirs)) {
    my $this_path = "$dir/$relative_path";
    if(-e $this_path) {
      $full_path = $this_path;
      last;
    }
  }
  return $full_path;
}

sub fresh_form_info_exists {
  my $self = shift;
  my $step = shift;
  my $return = 0;
  if($self->non_empty_val_ref($step) && $self->info_exists($step, $self->this_form)) {
    $return = 1;
  }
  return $return;
}

sub non_empty_val_ref {
  my $self = shift;
  my $step = shift;
  
  my $val_hash = $self->get_validate_ref($step);
  return $self->non_empty_ref($val_hash);
}

sub non_empty_ref {
  my $self = shift;
  my $ref = shift;
  my $non_empty = 0;
  if($ref) {
    my $ref_ref = ref $ref;
    if($ref_ref) {
      if($ref_ref eq 'HASH') {
        $non_empty = (scalar keys %{$ref}) ? 1 : 0;
      } elsif($ref_ref eq 'ARRAY') {
        $non_empty = (@{$ref}) ? 1 : 0;
      }
    }
  }
  return $non_empty;
}

sub info_exists {
  my $self = shift;
  my $step = shift;
  my $form = shift || $self->form;
  
  my $val_ref = $self->get_validate_ref($step);

  my $return = 0;
  #If the validate_ref default to true
  unless($self->non_empty_ref($val_ref)) {
    $return = 1;
  }
  
  my $validating_keys = $self->get_validating_keys($val_ref);
  #if there exists one key in the form that matches
  #one key in the validate_ref return true
  foreach(@{$validating_keys}) {
    if(exists $form->{$_}) {
      $return = 1;
    } 
  }
  return $return;
}

sub get_validating_keys {
  my $self = shift;
  my $val_ref = shift;
  my $val_ref_ref = ref $val_ref;
  my $validating_keys = [];
  if($val_ref_ref) {
    if($val_ref_ref eq 'ARRAY') {
      foreach my $array_ref (@{$val_ref}) {
        for(my $i=0;$i<@{$array_ref};$i++) {
          if($array_ref->[$i] eq '-key' && $array_ref->[$i+1]) {
            push @{$validating_keys}, $array_ref->[$i+1] unless(grep {$_ eq $array_ref->[$i+1]} @{$validating_keys});
            last;
          }
        }
      }
    } else {
      die "need to validate on non-ARRAY refs";
    }


  }
  return $validating_keys;

}

sub page_has_displayed {
  my $self = shift;
  my $page = shift;
  return (grep /^$page$/, @{$self->form->{_printed_pages}});
}

sub page_was_just_printed {
  my $self = shift;
  my $page = shift;
  return (
    #Were we passed a page
    $page
     &&
    #Do we have any record of printed_pages
    ($self->form->{_printed_pages})
     &&
    #Is that record an array
    (ref $self->form->{_printed_pages} eq 'ARRAY')
     &&
    #Is there at least two items in this array
    ( scalar @{$self->form->{_printed_pages}})
     &&
    #Is the one before the current the page we were passed
    $self->form->{_printed_pages}[-1] eq $page
  );
}

sub validate {
  my $self = shift;
  my $validated = $self->form->{_validated} || {};

  my $this_step = $self->{this_step}{this_step};
  my $return = 1;

  my $show_errors = 1;
  if(!$self->page_was_just_printed($this_step)) {
    $show_errors = 0;
  }

  my $method_pre_val = "$self->{this_step}{this_step}_pre_validate";
  if($self->can($method_pre_val)) {
    $return = $self->$method_pre_val($show_errors) && $return;
  }

  if($validated->{$this_step}) {


  } else {

    if($self->validate_proper($self->form, $self->{this_step}{validate_ref})) {

      $return = 0;

    } else {
      $self->{validated_fresh}{$this_step} = 1;
      $validated->{$this_step} = 1;
      my $validated_hash = {
        _validated => $validated,
      };

      $self->validate_unvalidated_keys($self->get_validating_keys($self->{this_step}{validate_ref}));

      $self->form->{_validated} = $validated;
      # going to save the keys that have been validated to the session
      foreach my $key (@{$self->get_validating_keys($self->{this_step}{validate_ref})}) {
        $validated_hash->{$key} = $self->form->{$key};
      }
      $self->session($validated_hash);
    }
  }
  my $method_post_val = "$self->{this_step}{this_step}_post_validate";
  if($self->can($method_post_val)) {
    $return = $self->$method_post_val($show_errors) && $return;
  }
  if(!$return) {
    my $change = '';
    foreach my $check_page ($this_step, @{$self->pages_after_page($this_step)}) {
      $change .= (delete $validated->{$check_page}||'');
    }
    if($change) {
      $self->session({
        _validated => $validated,
      });
    }
  }
  return $return;
}

sub validate_proper {
  my $self = shift;
  my $form = shift;
  my $val_ref = shift;
  require Embperl::Form::Validate;
  my $epf = new Embperl::Form::Validate($val_ref);
  my $ret = $epf->validate_messages($form);
  $self->{my_form}{js_validation} = $epf->get_script_code;
  my $return = $self->add_my_error($ret);
  return $return;
}

sub save_value {
  my $self = shift;
  my $name = shift;

  if (!ref $name) {
    $self->session({
      $name => $self->form->{$name}
    });
  } else {
    foreach my $key (keys %{$name}) {
      $self->form->{$key} = $name->{$key};
    }
    $self->session->save($name);
  }
}

sub clear_value {
  my $self = shift;
  my $name = shift;

  delete $self->form->{$name};
  delete $self->session->{form}{$name};
  delete $self->fill->{$name};
  $self->save_value($name => undef);
}

sub add_my_error {
  my $self = shift;
  my $errors = shift;
  my $added = 0;
  $self->{my_form}{error} ||= [];
  foreach my $error_array (GET_VALUES($errors)) {
    foreach my $error (GET_VALUES($error_array)) {
      next unless($error);
      $added++;
      push @{$self->{my_form}{error}}, $error;
    }
  }
  return $added;
}

sub fill {
  my $self = shift;
  $self->{fill} ||= {};
  return $self->{fill};
}

sub add_to_fill {
  my $self = shift;
  my $fill_to_add = shift;
  foreach(keys %{$fill_to_add}) {
    $self->fill->{$_} = $fill_to_add->{$_};
  }
}

sub print {
  my $self = shift;
  my $step = shift;

  $self->handle_unvalidated_keys;


  if (!-e $self->get_full_path($self->step_with_extension($step, $self->{htm_extension}))) {
    die "couldn't find content for page: $step";
    #$self->create_page($step);
  }

  $self->record_page_print;
  $self->process($self->step_with_extension($step, $self->{htm_extension}));
}

sub uber_form {
  my $self = shift;
  $self->{uber_form} ||= {};
  $self->{uber_form}{fill} ||= {};
  foreach (keys %{$self->form}) {
    next if(/^_/);
    $self->{uber_form}{$_} = $self->form->{$_};
  }
  foreach (keys %{$self->{my_form}}) {
    $self->{uber_form}{$_} = $self->{my_form}->{$_};
  }
  foreach (keys %{$self->fill}) {
    next if(/^_/);
    $self->{uber_form}{fill}{$_} = $self->fill->{$_};
  }
  $self->{uber_form}{script_name} = $ENV{SCRIPT_NAME} || '';
  return $self->{uber_form};
}

sub process {
  my $self = shift;
  my $step_filename = shift;
  $self->content_type;
  $self->template->process($step_filename, $self->uber_form
    #O::FORMS::get_required_hash($self->{this_step}{validate_ref}),
    #$self->{this_step}{validate_errors},
    #$self->{my_form},
    #$self->{form},
    #{
    #  more_content => $self->{this_step}{more_content},
    #  prev_step    => $self->{this_step}{previous_step},
    #},
  ) || die $self->template->error();
}

sub step_with_extension {
  my $self = shift;
  my $step = shift;
  my $extension_type = shift;
  return "$step." . $self->{"${extension_type}_extension"};
}

sub template {
  require Template;
  my $self = shift;
  unless($self->{template}) {
    $self->{template} = Template->new({
      INCLUDE_PATH => $self->include_path,
    });
  }
  return $self->{template};
}

sub record_mail_print {
  my $self = shift;
  my $step = shift;
  my $printed_mail = $self->session->{printed_mail} || [];
  unless($step && $printed_mail->[-1] && $step eq $printed_mail->[-1]) {
    push @{$printed_mail}, $step;
    $self->session({
      printed_mail => $printed_mail,
    });
  }
}

sub record_page_print {
  my $self = shift;
  my $step = shift || $self->{this_step}{this_step};
  my $printed_pages = $self->session->{_printed_pages} || [];
  unless($step && $printed_pages->[-1] && $step eq $printed_pages->[-1]) {
    push @{$printed_pages}, $step;
    $self->session({
      _printed_pages => $printed_pages,
    });
  }
}

# This subroutine will generate a generic HTML page 
# with form fields for the required fields based on the .val file
sub create_page {
  my $self = shift;
  my $step = shift;

  my $validate_ref = $self->get_validate_ref($self->{this_step}{this_step});
  my $content  = '[var text "content:path/signup/signup.txt"]';
  $content .= "<!-- this step nicely created: " . $self->my_content . "/" . $self->{this_step}{this_step} . " -->\n";
  $content .= '<HTML>';
  $content .= '<HEAD>';
  $content .= '<TITLE> created step: '. $self->my_content;
  $content .= '/' . $self->{this_step}{this_step} .'</TITLE>';
  $content .= "</HEAD>\n";
  $content .= "<BODY>\n";
  $content .= "[form.js]\n";
  $content .= "[forms.path_form]\n";

  $content .= "<CENTER>\n";
  $content .= "[form.more_content]\n";
  $content .= "<TABLE>\n";
  for my $name ( $self->get_validating_keys($validate_ref)) {
    $content .= '<TR><TD align="right">';
    $content .= $name;
    $content .= '</TD><TD>';
    $content .= "<INPUT TYPE='TEXT' NAME='$name' />";
    $content .= "[form.$name"."_required]";
    $content .= "[|| form.$name"."_error env.blank]";
    $content .= "<BR>\n";
    $content .= "</TD></TR>\n";
  }
  $content .= '<TR><TD colspan="2" align="right">';
  unless($self->{this_step}{this_step} eq $self->{path_array}[0]) {
    $content .= "[button.path_back]\n";
  }
  $content .= '<INPUT TYPE="SUBMIT" NAME="NEXT" VALUE="NEXT"/>';
  $content .= "</TD></TR>\n";
  $content .= '</TABLE>';
  $content .= '</CENTER>';
  $content .= "</FORM>\n";
  $content .= '</BODY>';
  $content .= '</HTML>';

  return $content;
}


sub GET_VALUES {
  my $values=shift;
  return () unless defined $values;
  if (ref $values eq "ARRAY") {
    return @$values;
  }
  return ($values);
}

sub URLEncode {
  my $arg = shift;
  my ($ref,$return) = ref($arg) ? ($arg,0) : (\$arg,1) ;

  if (ref($ref) ne 'SCALAR') {
    die "URLEncode can only modify a SCALAR ref!: ".ref($ref);
    return undef;
  }

  if ( (defined $$ref) && length $$ref) {
    $$ref =~ s/([^\w\.\-\ \@\/\:])/sprintf("%%%02X",ord($1))/eg;
    $$ref =~ y/\ /+/;
  }

  return $return ? $$ref : '';
}

sub content_type {
  unless($ENV{CONTENT_TYPED}) {
    print "Content-type: text/html\n\n";
  }
}

sub location_bounce {
  my $self = shift;
  my $url = shift;
  my $referer = shift;
  if (exists $ENV{CONTENT_TYPED}) {
    print "Location: <a href='$url'>$url</a><br>\n";
  } else {
    print "Status: 302\r\n";
    print "Referer: $referer\r\n" if($referer);
    print "Location: $url\r\n\r\n";
  }
  return 1;
}

1;

__END__

=head1 NAME

CGI::Path - module to aid in traversing one or more paths

=head1 SYNOPSIS

CGI::Path allows for easy navigation through a set of steps, a path.  It uses a session extensively (managed
by default via Apache::Session) to hopefully simplify path based cgis.

=head1 A PATH

A path is a package, like CGI::Path::Skel.  The path needs to be @ISA CGI::Path.  The package can contain
the step methods as described below.  You can also make a directory for the path, 
like CGI/Path/Skel, where the direectory will contain a package for each step.  This could be done from
your $ENV{PERL5LIB}.

=head1 path_hash

The path_hash is what helps generate the path_array, which is just an array of steps.  It is a hash to 
allow for easy overrides, since it is sort
of hard to override the third element of an array through a series of news.

The path_hash needs a key named 'initial_step', and then steps that point down the line, like so

  path_hash => {
    initial_step => 'page_one',
    page_one     => 'page_two',
    page_two     => 'page_three',
  },

since page_three doesn't point anywhere, the path_array ends.  You can just override $self->path_hash,
and have it return a hash ref as above.

It is quite easy to look at $ENV{PATH_INFO} and control multiple paths through a single cgi.  I offer the
following as a simple example

sub path_hash {
  my $self = shift;
  my $sub_path = '';
  if($ENV{PATH_INFO} && $ENV{PATH_INFO} =~ m@/(\w+)@) {
    $sub_path = $1;
  }
  my $sub_path_hash = {
    '' => {
      initial_step => 'main',
      main         => '',
    },
  };

  ### this is the generic path for adding something
  if($sub_path =~ /^add_(\w+)$/ && !exists $sub_path_hash->{$sub_path}) {
    $sub_path_hash->{$sub_path} = {
      initial_step          => $sub_path,
      $sub_path             => "${sub_path}_confirm",
      "${sub_path}_confirm" => "${sub_path}_receipt",
    };
  }
  $sub_path = '' unless(exists $sub_path_hash->{$sub_path});
  return $sub_path_hash->{$sub_path};
}

The above path_hash method was used to manage a series of distinct add paths.  Distinct paths added users,
categories, blogs and entries.  Each path was to handled differently, but they each had a path similar to the
add_user path, which looked like this

add_user => add_user_confirm => add_user_receipt

=head1 my_module

my_module by default is something like CGI::Path::Skel.  You can override $self->my_module and have it
return a scalar containing your my_module.  Module overrides are done based on my_module.

=head1 my_content

my_module by default is something like path/skel.  It defaults to a variant of my_module.  You can
override $self->my_content and have it return a scalar your my_content.  html content gets printed based
on my_content.

=head1 path_array

The path_array is formed from path_hash.  It is an array ref of the steps in the path.

=head1 navigate

$self->navigate walks through a path of steps, where each step corresponds to a .htm content
file and a .val validation hash.

A step corresponds to a .htm content file.  The .htm and .val need to share the base same name.

$self->{this_step} is hash ref containing the following
previous_step => the last step
this_step     => the current step
validate_ref  => the validation ref for the current step

Generally, navigate generates the form (see below), and for each step does the following

--  Get the validate ref (val_ref) for the given page
--  Comparing the val_ref to the form see if info exists for the step
--  Validate according to the val_ref
--  If validation fails, or if info doesn't exist, process the page and stop

More specifically, the following methods can be called for a step, in the given order.

step                    details/possible uses
---------------------------------------------
${step}_hook_pre        initializations, 
                        must return 0 or step gets skipped
info_exists             checks to see if you have info for this step
${step}_info_complete   can be used to make sure you have all the info you need

validate                contains the following
${step}_pre_validate    stuff to check before validate proper
validate_proper         runs the .val file validation
${step}_post_validate   stuff to run after validate proper

${step}_hash_fill       return a hash ref of things to add to $self->fill
                        fill is a hash ref of what fills the forms
${step}_hash_form       perhaps set stuff for $self->{my_form}
                        my_form is a hash ref that gets passed to the process method
${step}_hash_errors     set errors
${step}_step            do actual stuff for the step
${step}_hook_post       last chance

=head1 generate_form

The goal is that the programmer just look at $self->form for form or session information.  
To help facilitate this goal, I use the following

$self->this_form           - form from the current hit
$self->{session_only} = [] - things that get deleted from this_form and get inserted from the session
$self->{session_wins} = [] - this_form wins by default, set this if you want something just from the session

The code then sets the form with the following line

$self->{form} = {%{$self->session}, %{$this_form}, %{$form}};

=head1 Session management

CGI::Path uses Apache::Session::File by default for session management.  If you use this default you will need to write the following methods

session_dir      - returns the directory where the session files will go
session_lock_dir - returns the directory where the session lock files will go

=cut
