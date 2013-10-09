class Program
  include Mongoid::Document
  include Mongoid::Timestamps

  field :prgm_id,             type: Integer
  field :company_name,        type: String
  field :logo_img,            type: String
  field :site_address,        type: String
  field :categories,          type: String
  field :mobile_tracking,     type: String
  field :status,              type: String
  field :description,         type: String
  field :contact_info,        type: Array
  field :offer_terms,         type: Array
  field :offer_note,          type: String
  field :coockie_duration,    type: Array
  field :lock_period,         type: Array
  field :promo_methods,       type: Array
  field :suggested_keywords,  type: String
  field :restricted_keywords, type: String
  field :bidding_policy,      type: Array

end
