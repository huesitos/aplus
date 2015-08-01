# A topic is used to organize cards. It has a title, and a recall_percentage
# The title must be present. Also, the recall_percentage must be a number between
# 0 and 1, including them. It may belong to a subject. It can be set for reviewing.
# When a topic is set for reviewing, the user receives a notification when any card's
# review date is today. If a topic is destroyed, its cards are also destroyed.
# If the subject it belongs to is archived, then the topic is also archived.
class Topic
  include Mongoid::Document
  field :title, type: String

  has_many :cards, dependent: :destroy
  has_many :topic_configs, dependent: :destroy

  belongs_to :subject
  belongs_to :user

  validates :title, presence: true
  validates_associated :cards

  # Finds all the topics that belong to a user based on the user_id
  def self.from_user(user_id)
    Topic.where(user_id: user_id)
  end

  # Moves all the cards back to level 1.
  def reset_cards(user_id)
    card_ids = self.cards.pluck(:_id)
    
    card_statistics = CardStatistic.where(card_id: {"$in" => card_ids}, user_id: user_id)

    card_statistics.each { |cs| cs.reset }
  end

  # Returns all the topics that have to be reviewed today, with the number of cards
  # they have and the approximate amount of time it will take to study it
  def self.topics_to_study(user_id, date)
    study_topics = []
    topic_ids = TopicConfig.from_user(user_id).not_archived.reviewing.pluck(:topic_id)
    topics = Topic.where(:_id => { "$in" => topic_ids })

    # If the date it's going to look for the topics to study is today, also pick
    # all the cards with a review date from previous days.
    if date <= Date.today
      card_ids = CardStatistic.where(
        :user_id => user_id, 
        :review_date => {"$lte" => date}).pluck(:card_id)
    else
      card_ids = CardStatistic.where(
        :user_id => user_id, 
        :review_date => {"$gt" => date, "$lt" => date+1}).pluck(:card_id)

      CardStatistic.where(:user_id => user_id, :review_date => {"$lt" => date}).each do |cs|

        # Calculate the next review dates as long as it doesn't go beyond "date".
        # If the review date happens to be equal to "date", then add it to the cards
        # that have to be studied that day
        n = 1
        rd = cs.card_review_projection(cs.review_date, cs.level+n)

        while rd < date
          n += 1
          rd = cs.card_review_projection(rd, cs.level+n)
        end
        
        if rd.to_date == date
          card_ids << cs.card_id
        end
      end
    end

    topics.each do |t|
      cards = t.cards.where(:_id => { "$in" => card_ids })
      at = 0 # approximate time to answer everything

      if cards.count > 0
        cards.each do |c|
          cs = c.card_statistics.find_by(user_id: t.user.id)
          at += cs.approx_time_to_answer
        end

        study_topics.push({
          topic: t,
          cards_count: cards.length.to_i,
          approx_time: at.to_i
        })
      end
    end

    study_topics
  end

  # Returns all the cards that must be studied today for that user
  def cards_to_study(user_id)
    card_ids = CardStatistic.where(
      :review_date => {"$lte" => DateTime.now},
      :user_id => user_id).pluck(:card_id)
    cards = self.cards.where(:_id => { "$in" => card_ids.to_a })
    cards
  end

  # Shares the topic that belongs to another user, with the current user
  # It creates a new copy of the topic that belongs to the current user
  def share(recipient_id, subject_id)
    user = User.find(recipient_id)

    # makes a copy of the topic for the current user
    new_topic = user.topics.create(title: self.title)
    new_topic.topic_configs.create(user_id: user.id)

    new_topic.update(subject_id: subject_id) if subject_id

    # copies all the cards in topic to the new topic
    self.cards.each do |card|
      new_card = new_topic.cards.create(front: card.front,
        back: card.back)
      new_card.card_statistics.create(user_id: user.id)
    end
  end

  # Adds a new collaborator to the topic
  def add_collaborator(recipient_id)
    if self.topic_configs.find_by(user_id: recipient_id).nil?
      self.topic_configs.create(user_id: recipient_id)

      self.cards.each do |card|
        card.card_statistics.create(user_id: recipient_id)
      end
    end
  end

  # Adds a remove collaborator to the topic
  def remove_collaborator(recipient_id)
    topic_config = self.topic_configs.find_by(user_id: recipient_id)
    if topic_config
      topic_config.destroy

      # Destroy the card_statistic related to the removed collaborator
      self.cards.each do |card|
        cs = card.card_statistics.find_by(user_id: recipient_id)
        cs.destroy
      end
    end
  end
end
