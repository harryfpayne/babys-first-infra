FROM golang

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY *.go ./

# Build
RUN CGO_ENABLED=0 GOOS=linux go build -o /main

EXPOSE 8080

# Run
CMD ["/main"]