class User < ActiveRecord::Base
  include Student, Teacher
  has_secure_password validations: false

  validates :password,              confirmation: { if: :permanent? },
                                    presence:     { if: :permanent?, on: :create }
  validates :password_confirmation, presence:     { if: ->(m) { m.password.present? && m.permanent? } }
  validates :email,                 uniqueness:   { case_sensitive: false, allow_blank: true },
                                    presence:     { if: ->(m) { m.teacher? || m.username.blank? } }
  validates :username,              presence:     { if: ->(m) { m.email.blank? && m.permanent? } },
                                    uniqueness:   { case_sensitive: false, allow_blank: true }
  validates :terms_of_service,      acceptance:   { on: :create }

  ROLES      = %w(student teacher temporary user admin)
  SAFE_ROLES = %w(student teacher)
  default_scope -> { where('role != ?', 'temporary') }
  attr_accessor :newsletter

  after_create :subscribe_to_newsletter

  def safe_role_assignment role
    self.role = if sanitized_role = SAFE_ROLES.find{ |r| r == role.strip }
      sanitized_role
    else
      'user'
    end
  end

  # def authenticate
  def self.authenticate params
    user   = User.where('LOWER(email) = LOWER(?)', params[:email]).first
    user ||= User.where('LOWER(username) = LOWER(?)', params[:email]).first
    user.try(:authenticate, params[:password])
  end

  def after_initialize!
    if save
      UserMailer.welcome_email(self).deliver! if email.present?
      true
    else
      false
    end
  end

  def role
    @role_inquirer ||= ActiveSupport::StringInquirer.new(self[:role])
  end

  def role= role
    remove_instance_variable :@role_inquirer if defined?(@role_inquirer)
    super
  end

  def password?
    password.present?
  end

  def student?
    role.student?
  end

  def teacher?
    role.teacher?
  end

  def admin?
    role.admin?
  end

  def permanent?
    !role.temporary?
  end

  def refresh_token!
    update_attributes token: SecureRandom.urlsafe_base64
  end

  def first_name= first_name
    last_name
    @first_name = first_name
    set_name
  end

  def last_name= last_name
    first_name
    @last_name = last_name
    set_name
  end

  def first_name
    @first_name ||= name.to_s.split("\s")[0]
  end

  def last_name
    @last_name ||= name.to_s.split("\s")[-1]
  end

  def set_name
    self.name = [@first_name, @last_name].compact.join(' ')
  end

  def generate_username
    self.username = "#{first_name}.#{last_name}@#{classcode}"
  end

  def generate_password
    self.password = self.password_confirmation = last_name
  end

  def generate_student
    self.role = 'student'
    generate_username
    generate_password
  end

private

  def newsletter?
    return false if newsletter.blank?
    newsletter != '0'
  end

  def subscribe_to_newsletter
    MailchimpConnection.connection.lists.subscribe('eadf6d8153', { email: email }, merge_vars=nil, email_type='html', double_optin=false, update_existing=false, replace_interests=true, send_welcome=false) if newsletter?
  end
end
