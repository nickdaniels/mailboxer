class Receipt < ActiveRecord::Base
  attr_accessible :trashed, :is_read if Mailboxer.protected_attributes?

  belongs_to :notification, :validate => true, :autosave => true
  belongs_to :receiver, :polymorphic => :true
  belongs_to :message, :foreign_key => "notification_id"

  validates_presence_of :receiver

  scope :recipient, lambda { |recipient|
    where(:receiver_id => recipient.id,:receiver_type => recipient.class.base_class.to_s)
  }
  #Notifications Scope checks type to be nil, not Notification because of STI behaviour
  #with the primary class (no type is saved)
  scope :notifications_receipts, lambda { joins(:notification).where('notifications.type' => nil) }
  scope :messages_receipts, lambda { joins(:notification).where('notifications.type' => Message.to_s) }
  scope :notification, lambda { |notification|
    where(:notification_id => notification.id)
  }
  scope :conversation, lambda { |conversation|
    joins(:message).where('notifications.conversation_id' => conversation.id)
  }
  scope :sentbox, lambda { where(:mailbox_type => "sentbox") }
  scope :inbox, lambda { where(:mailbox_type => "inbox") }
  scope :trash, lambda { where(:trashed => true) }
  scope :not_trash, lambda { where(:trashed => false) }
  scope :is_read, lambda { where(:is_read => true) }
  scope :is_unread, lambda { where(:is_read => false) }
  scope :ordered, lambda { order('receipts.created_at ASC') }

  after_validation :remove_duplicate_errors
  class << self
    #Marks all the receipts from the relation as read
    def mark_as_read(options={})
      update_receipts({:is_read => true, :updated_at => Time.now}, {:is_read => false}.merge(options))
    end

    #Marks all the receipts from the relation as unread
    def mark_as_unread(options={})
      update_receipts({:is_read => false, :updated_at => Time.now}, {:is_read => true}.merge(options))
    end

    #Marks all the receipts from the relation as trashed
    def move_to_trash(options={})
      update_receipts({:trashed => true, :updated_at => Time.now}, {:trashed => false}.merge(options))
    end

    #Marks all the receipts from the relation as not trashed
    def untrash(options={})
      update_receipts({:trashed => false, :updated_at => Time.now}, {:trashed => true}.merge(options))
    end

    #Moves all the receipts from the relation to inbox
    def move_to_inbox(options={})
      update_receipts({:mailbox_type => :inbox, :trashed => false, :updated_at => Time.now}, {:mailbox_type => :sentbox}.merge(options))
    end

    #Moves all the receipts from the relation to sentbox
    def move_to_sentbox(options={})
      update_receipts({:mailbox_type => :sentbox, :trashed => false, :updated_at => Time.now}, {:mailbox_type => :inbox}.merge(options))
    end

    #This methods helps to do a update_all with table joins, not currently supported by rails.
    #Acording to the github ticket https://github.com/rails/rails/issues/522 it should be
    #supported with 3.2.
    def update_receipts(updates,options={})
      conversation.touch # update the conversation timestamp

      ids = Array.new
      where(options).each do |rcp|
        ids << rcp.id
      end
      unless ids.empty?
        conditions = [""].concat(ids)
        condition = "id = ? "
        ids.drop(1).each do
          condition << "OR id = ? "
        end
        conditions[0] = condition
        Receipt.except(:where).except(:joins).where(conditions).update_all(updates)
      end
    end
  end

  #Marks the receipt as read
  def mark_as_read
    update_attributes(:is_read => true, :updated_at => Time.now) unless is_read?
  end

  #Marks the receipt as unread
  def mark_as_unread
    update_attributes(:is_read => false, :updated_at => Time.now) unless is_unread?
  end

  #Marks the receipt as trashed
  def move_to_trash
    update_attributes(:trashed => true, :updated_at => Time.now) unless is_trashed?
  end

  #Marks the receipt as not trashed
  def untrash
    update_attributes(:trashed => false, :updated_at => Time.now) if is_trashed?
  end

  #Moves the receipt to inbox
  def move_to_inbox
    update_attributes(:mailbox_type => :inbox, :trashed => false, :updated_at => Time.now) unless mailbox_type == 'inbox'
  end

  #Moves the receipt to sentbox
  def move_to_sentbox
    update_attributes(:mailbox_type => :sentbox, :trashed => false, :updated_at => Time.now) unless mailbox_type == 'sentbox'
  end

  #Returns the conversation associated to the receipt if the notification is a Message
  def conversation
    message.conversation if message.is_a? Message
  end

  #Returns if the participant have read the Notification
  def is_unread?
    !self.is_read
  end

  #Returns if the participant have trashed the Notification
  def is_trashed?
    self.trashed
  end

  protected

  #Removes the duplicate error about not present subject from Conversation if it has been already
  #raised by Message
  def remove_duplicate_errors
    if self.errors["notification.conversation.subject"].present? and self.errors["notification.subject"].present?
      self.errors["notification.conversation.subject"].each do |msg|
        self.errors["notification.conversation.subject"].delete(msg)
      end
    end
  end

  if Mailboxer.search_enabled && Mailboxer.search_engine != :elasticsearch
    searchable do
      text :subject, :boost => 5 do
        message.subject if message
      end
      text :body do
        message.body if message
      end
      integer :receiver_id
    end
  end
end
