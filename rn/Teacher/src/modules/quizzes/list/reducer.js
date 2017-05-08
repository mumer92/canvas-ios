/* @flow */

import { Reducer } from 'redux'
import { asyncRefsReducer } from '../../../redux/async-refs-reducer'
import { handleActions } from 'redux-actions'
import handleAsync from '../../../utils/handleAsync'
import Actions from './actions'
import i18n from 'format-message'

const { refreshQuizzes } = Actions

export const refs: Reducer<AsyncRefs, any> = asyncRefsReducer(
  refreshQuizzes.toString(),
  i18n('There was a problem loading the quizzes.'),
  ({ result }) => result.data.map(quiz => quiz.id)
)

export const entities: Reducer<QuizzesState, any> = handleActions({
  [refreshQuizzes.toString()]: handleAsync({
    resolved: (state, { result }) => {
      const incoming = result.data
        .reduce((incoming, quiz) => ({
          ...incoming,
          [quiz.id]: {
            data: quiz,
            pending: 0,
            error: null,
          },
        }), {})
      return { ...state, ...incoming }
    },
  }),
}, {})
