# frozen_string_literal: true

# The one collapsed card a report keeps its explanations in (design-rules >
# Where a Rule or a How-To Goes). Its label is spelled here once: a test that
# expects the card gone would keep passing against a label that had merely been
# reworded, and nothing would say so.
module ReportCardTestHelper
  REPORT_CARD_LABEL = "About This Report"

  # Where a card keeps its questions. Spelled once for the same reason as the
  # label: the check that a question is gone must look where the check that it
  # is there looked.
  CARD_QUESTION = "details dt"

  # One card a page, so the default is exactly one. Pass count: 0 for a state of
  # the page that must not offer it.
  def assert_report_card(count: 1)
    assert_select("details summary", text: REPORT_CARD_LABEL, count:)
  end

  # The answer under one question in a page's card, as text. Fails when the
  # question is not there, or when what follows it is not its answer.
  def card_answer(question)
    answer = assert_select(CARD_QUESTION, text: question).first.next_element
    assert_equal "dd", answer&.name, "nothing answers #{question.inspect}"

    answer.text.squish
  end

  # For a state of the page that must not offer one pair. Read the question with
  # card_answer first, in the state that has it: against a question that was
  # never on the page this passes and says nothing.
  def assert_no_card_question(question)
    assert_select(CARD_QUESTION, text: question, count: 0)
  end
end
