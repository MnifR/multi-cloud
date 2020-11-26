var express = require('express');
var path = require('path');
var cookieParser = require('cookie-parser');
var logger = require('morgan');

var indexRouter = require('./routes/index');
var personsRouter = require('./routes/persons');
var healthRouter = require('./routes/health');

var usersRouter = require('./routes/users');
var app = express();

app.use(logger('dev'));
app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(cookieParser());
app.use(express.static(path.join(__dirname, 'public')));

app.use('/', indexRouter);
app.use('/health', healthRouter);
app.use('/persons', personsRouter);
app.use('/users', usersRouter);

module.exports = app;
