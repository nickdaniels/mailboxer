class AddConversationType < ActiveRecord::Migration

  def change
    change_table :conversations do |t|
      t.string :conversation_type, default: 'Message'
    end
  end
  
end
