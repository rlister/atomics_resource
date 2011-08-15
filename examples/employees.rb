#!/usr/bin/env ruby

## this does not run, but will show you how to configure against your local Atomics instance

require 'rubygems'
require 'atomics_resource'

ATOMICS_CONFIG = {
  'hr' => {
    'host' => 'hr-atomics.newco.com',
    'port' => '8080',
    'path' => '/jAtomics/select/?version=1',
  },
  'other' => {
    'host' => 'other-atomics.for.illustration.com',
    'port' => '80',
    'path' => '/atomics/raw',
  },
}

class Employee < AtomicsResource::Base
  set_atomics_type :hr
  set_table_name   :employee_display
  set_primary_key  :id

  column :first_name
  column :last_name
  column :title
  column :team_id
end

employees = Employee.all(:conditions => {:team_id => 1},
                         :order      => [:last_name, :first_name])

employees.each do |e|
  puts "#{e.last_name},#{e.first_name}: #{e.title}"
end
