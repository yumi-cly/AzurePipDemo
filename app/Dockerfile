# Use the official Node.js image as a base
FROM node:14

# Set environment to production
ENV NODE_ENV=production

# Set the working directory
WORKDIR /app

# Copy package.json and package-lock.json
COPY package.json package-lock.json ./

# Install dependencies
RUN npm install --production

# Copy the rest of the application
COPY . .

# Expose the port the app runs on
EXPOSE 8080

# Command to run the app
CMD ["node", "server.js"]

