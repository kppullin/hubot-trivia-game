# Description:
#   Play trivia! Doesn't include questions. Questions should be in the following JSON format:
#   {
#       "answer": "Pizza",
#       "category": "FOOD",
#       "question": "Crust, sauce, and toppings!",
#       "value": "$400"
#   },
#
# Dependencies:
#   cheerio - for questions with hyperlinks
#
# Configuration:
#   None
#
# Commands:
#   !trivia - ask a question
#   !skip - skip the current question
#   !answer <answer> or !a <answer> - provide an answer
#   !hint or !h - take a hint
#   !score <player> - check the score of the player
#   !scores or !score all - check the score of all players
#
# Author:
#   yincrash

Fs = require 'fs'
Path = require 'path'
Cheerio = require 'cheerio'
AnswerChecker = require './answer-checker'

class Game
  @currentQ = null
  @hintLength = null

  constructor: (@robot) ->
    buffer = Fs.readFileSync(Path.resolve('./res', 'questions.json'))
    @questions = JSON.parse buffer
    @robot.logger.debug "Initiated trivia game script."

  askQuestion: (resp) ->
    unless @currentQ # set current question
      index = Math.floor(Math.random() * @questions.length)
      @currentQ = @questions[index]
      @hintLength = 0
      @robot.logger.debug "Answer is #{@currentQ.answer}"
      # remove optional portions of answer that are in parens
      @currentQ.validAnswer = @currentQ.answer.replace /\(.*?\)\s?/g, ""
      # remove leading and trailing quotes
      @currentQ.validAnswer = @currentQ.validAnswer.replace /^"|"$/g, ""
      @currentQ.validAnswer = @currentQ.validAnswer.trim()

      @currentQ.value = @randomValue() if !@currentQ.value?

    $question = Cheerio.load ("<span>" + @currentQ.question + "</span>")
    link = $question('a').attr('href')
    text = $question('span').text()
    resp.send "Answer with !a or !answer\n" +
              "For #{@currentQ.value} in the category of #{@currentQ.category}:\n" +
              "#{text} " +
              if link then " #{link}" else ""

  skipQuestion: (resp) ->
    if @currentQ
      resp.send "The answer is #{@currentQ.answer}."
      @currentQ = null
      @hintLength = null
      @askQuestion(resp)
    else
      resp.send "There is no active question!"

  answerQuestion: (resp, guess) ->
    if @currentQ
      # remove html entities (slack's adapter sends & as &amp; now)
      checkGuess = guess.replace /&.{0,}?;/, ""

      # remove all punctuation and spaces, and see if the answer is in the guess.
      checkGuess = @normalizeAnswer(checkGuess)
      checkAnswer = @normalizeAnswer(@currentQ.validAnswer)

      if AnswerChecker(checkGuess, checkAnswer)
        resp.reply "YOU ARE CORRECT!!1!!!111!! The answer is #{@currentQ.answer}"
        name = resp.envelope.user.name.toLowerCase().trim()
        value = @currentQ.value.replace /[^0-9.-]+/g, ""
        @robot.logger.debug "#{name} answered correctly."
        user = resp.envelope.user
        user.triviaScore = user.triviaScore or 0
        user.triviaScore += parseInt value
        resp.reply "Score: #{user.triviaScore}"
        @robot.brain.save()
        @currentQ = null
        @hintLength = null

        @askQuestion(resp)
      else
        resp.send "#{guess} is incorrect."
    else
      resp.send "There is no active question!"

  normalizeAnswer: (answer) ->
    # remove leading 'a', 'an', 'the'
    normalized = answer.toLowerCase().replace /^(a(n?)|the)\s/g, ""
    # remove punctuation
    normalized = normalized.replace /[\\'"\.,-\/#!$%\^&\*;:{}=\-_`~()\s]/g, ""

  hint: (resp, extendedHint) ->
    if @currentQ
      answer = @currentQ.validAnswer.replace /^(a(n?)|the)\s/i, ""
      answer = answer.trim()

      if extendedHint
        # When the `extenedHint` flag is true, expand the hint by the
        # MAX of (40% of the remaining hidden chars, 2)
        remainingChars = answer.length - @hintLength
        extLength = Math.max(Math.floor(remainingChars * .4), 2)
        @hintLength = @hintLength + extLength
      else
        @hintLength += 1

      # We may have exceeded the answer length via the increments above. Cap the length.
      @hintLength = Math.min(answer.length, @hintLength)

      hint = answer.substr(0,@hintLength) + answer.substr(@hintLength,(answer.length + @hintLength)).replace(/./g, ".")
      resp.send hint
    else
      resp.send "There is no active question!"

  checkScore: (resp, name) ->
    if name == "all"
      scores = ""
      for user in @robot.brain.usersForFuzzyName ""
        user.triviaScore = user.triviaScore or 0
        scores += "#{user.name} - $#{user.triviaScore}\n"
      resp.send scores
    else
      user = @robot.brain.userForName name
      unless user
        resp.send "There is no score for #{name}"
      else
        user.triviaScore = user.triviaScore or 0
        resp.send "#{user.name} - $#{user.triviaScore}"

  randomValue: ->
    # Try N times to find a question with a valid 'value'
    attempts = 0
    while attempts < 20
      index = Math.floor(Math.random() * @questions.length)
      value = @questions[index].value
      return value if value
      ++attempts

    # We still failed to find a valid value. Return a reasonable default
    "1000"

module.exports = (robot) ->
  game = new Game(robot)
  robot.hear /!trivia/i, (resp) ->
    game.askQuestion(resp)

  robot.hear /!skip/i, (resp) ->
    game.skipQuestion(resp)

  robot.hear /!a(nswer)? (.*)/, (resp) ->
    game.answerQuestion(resp, resp.match[2])

  robot.hear /!score (.*)/i, (resp) ->
    game.checkScore(resp, resp.match[1].toLowerCase().trim())

  robot.hear /!scores/i, (resp) ->
    game.checkScore(resp, "all")

  robot.hear /!h(int)?/i, (resp) ->
    extendedHint = resp.match[0][1] == "H";
    game.hint(resp, extendedHint)
